#include <stdlib.h>
#include <stdio.h>
#include <cstring> // needed for memset

#include <tune_quda.h>
#include <blas_quda.h>
#include <color_spinor_field.h>

#include <jitify_helper.cuh>
#include <kernels/multi_blas_core.cuh>

namespace quda {

  namespace blas {

    qudaStream_t* getStream();

    template <template <typename ...> class Functor, typename store_t, typename y_store_t,
              int nSpin, typename T, int NXZ_ = 1>
    class MultiBlas : public TunableVectorY
    {
      using real = typename mapper<y_store_t>::type;
      static constexpr int NXZ = isFixed<store_t>::value && NXZ_ == 128 ? 64 : NXZ_;
      const int NYW;
      Functor<real> f;
      int max_warp_split;
      mutable int warp_split; // helper used to keep track of current warp splitting
      const int nParity;
      const T &a, &b, &c;
      std::vector<ColorSpinorField *> &x, &y, &z, &w;
      const QudaFieldLocation location;

      bool tuneSharedBytes() const { return false; }

      // for these streaming kernels, there is no need to tune the grid size, just use max
      unsigned int minGridSize() const { return maxGridSize(); }

  public:
      MultiBlas(const T &a, const T &b, const T &c, const ColorSpinorField &x_meta, const ColorSpinorField &y_meta,
                std::vector<ColorSpinorField *> &x, std::vector<ColorSpinorField *> &y,
                std::vector<ColorSpinorField *> &z, std::vector<ColorSpinorField *> &w) :
        TunableVectorY(y.size()),
        NYW(y.size()),
        f(NXZ, NYW),
        warp_split(1),
        nParity(x[0]->SiteSubset()),
        a(a),
        b(b),
        c(c),
        x(x),
        y(y),
        z(z),
        w(w),
        location(checkLocation(*x[0], *y[0], *z[0], *w[0]))
      {
        checkLength(*x[0], *y[0], *z[0], *w[0]);
        auto x_prec = checkPrecision(*x[0], *z[0]);
        auto y_prec = checkPrecision(*y[0], *w[0]);
        auto x_order = checkOrder(*x[0], *z[0]);
        auto y_order = checkOrder(*y[0], *w[0]);
        if (x_prec == y_prec && x_order != y_order) errorQuda("Orders %d %d do not match", x_order, y_order);

        // check sizes are valid
        constexpr int NYW_max = max_YW_size<NXZ, store_t, y_store_t, decltype(f)>();
        constexpr int scalar_width = sizeof(typename decltype(f)::coeff_t) / sizeof(real);
        const int NYW_max_check = max_YW_size(x.size(), x[0]->Precision(), y[0]->Precision(), f.use_z, f.use_w, scalar_width, false);

        if (!is_valid_NXZ(NXZ, false, x[0]->Precision() < QUDA_SINGLE_PRECISION))
          errorQuda("NXZ=%d is not a valid size ( MAX_MULTI_BLAS_N %d)", NXZ, MAX_MULTI_BLAS_N);
        if (NYW_max != NYW_max_check) errorQuda("Compile-time %d and run-time %d limits disagree", NYW_max, NYW_max_check);
        if (NYW > NYW_max) errorQuda("NYW exceeds max size (%d > %d)", NYW, NYW_max);
        if (NXZ * NYW * scalar_width > MAX_MATRIX_SIZE)
          errorQuda("Coefficient matrix exceeds max size (%d > %d)", NXZ * NYW * scalar_width, MAX_MATRIX_SIZE);

        // heuristic for enabling if we need the warp-splitting optimization
        const int gpu_size = 2 * deviceProp.maxThreadsPerBlock * deviceProp.multiProcessorCount;
        switch (gpu_size / (x[0]->Length() * NYW)) {
        case 0: max_warp_split = 1; break; // we have plenty of work, no need to split
        case 1: max_warp_split = 2; break; // double the thread count
        case 2:                            // quadruple the thread count
        default: max_warp_split = 4;
        }
        max_warp_split = std::min(NXZ, max_warp_split); // ensure we only split if valid

        Amatrix_h = reinterpret_cast<signed char *>(const_cast<typename T::type *>(a.data));
        Bmatrix_h = reinterpret_cast<signed char *>(const_cast<typename T::type *>(b.data));
        Cmatrix_h = reinterpret_cast<signed char *>(const_cast<typename T::type *>(c.data));

        strcpy(aux, x[0]->AuxString());
        if (x[0]->Precision() != y[0]->Precision()) {
          strcat(aux, ",");
          strcat(aux, y[0]->AuxString());
        }

#ifdef JITIFY
        ::quda::create_jitify_program("kernels/multi_blas_core.cuh");
#endif

        apply(*getStream());
        checkCudaError();

        blas::bytes += bytes();
        blas::flops += flops();
      }

      TuneKey tuneKey() const
      {
        char name[TuneKey::name_n];
        strcpy(name, num_to_string<NXZ>::value);
        strcat(name, std::to_string(NYW).c_str());
        strcat(name, typeid(f).name());
        return TuneKey(x[0]->VolString(), name, aux);
      }

      template <typename buffer_t>
      void set_param(buffer_t &d, const T &h, const qudaStream_t &stream)
      {
        using coeff_t = typename decltype(f)::coeff_t;
        constexpr size_t n_coeff = MAX_MATRIX_SIZE / sizeof(coeff_t);

        coeff_t tmp[n_coeff];
        for (int i = 0; i < NXZ; i++)
          for (int j = 0; j < NYW; j++) tmp[NYW * i + j] = coeff_t(h.data[NYW * i + j]);
        cudaMemcpyToSymbolAsync(d, tmp, NXZ * NYW * sizeof(decltype(tmp[0])), 0, cudaMemcpyHostToDevice, stream);
        //cuMemcpyHtoDAsync(d, tmp, NXZ * NYW * sizeof(decltype(tmp[0])), stream);
      }

      void apply(const qudaStream_t &stream)
      {
        constexpr bool site_unroll = !std::is_same<store_t, y_store_t>::value || isFixed<store_t>::value;
        if (site_unroll && (x[0]->Ncolor() != 3 || x[0]->Nspin() == 2))
          errorQuda("site unroll not supported for nSpin = %d nColor = %d", x[0]->Nspin(), x[0]->Ncolor());

        TuneParam tp = tuneLaunch(*this, getTuning(), getVerbosity());

        if (location == QUDA_CUDA_FIELD_LOCATION) {
          // need to add native check here
          constexpr int N = n_vector<store_t, true, nSpin, site_unroll>();
          constexpr int Ny = n_vector<y_store_t, true, nSpin, site_unroll>();
          constexpr int M = site_unroll ? (nSpin == 4 ? 24 : 6) : N; // real numbers per thread
          const int length = x[0]->Length() / (nParity * M);

          MultiBlasArg<NXZ, store_t, N, y_store_t, Ny, decltype(f)> arg(x, y, z, w, f, NYW, length);

#ifdef JITIFY
          using namespace jitify::reflection;
          auto instance = program->kernel("quda::blas::multiBlasKernel")
            .instantiate(Type<real>(), M, NXZ, tp.aux.x, Type<decltype(arg)>());

          set_param(instant.get_constant_ptr("quda::blas::Amatrix_d"), a);
          set_param(instant.get_constant_ptr("quda::blas::Bmatrix_d"), b);
          set_param(instant.get_constant_ptr("quda::blas::Cmatrix_d"), c);

          tp.block.x *= tp.aux.x; // include warp-split factor
          jitify_error = instance.configure(tp.grid, tp.block, tp.shared_bytes, stream).launch(arg);
          tp.block.x /= tp.aux.x; // restore block size
#else
          if (a.data) { set_param(Amatrix_d, a, stream); }
          if (b.data) { set_param(Bmatrix_d, b, stream); }
          if (c.data) { set_param(Cmatrix_d, c, stream); }

          tp.block.x *= tp.aux.x; // include warp-split factor

          switch (tp.aux.x) {
          case 1: multiBlasKernel<real, M, NXZ, 1><<<tp.grid, tp.block, tp.shared_bytes, stream>>>(arg); break;
#ifdef WARP_SPLIT
          case 2: multiBlasKernel<real, M, NXZ, 2><<<tp.grid, tp.block, tp.shared_bytes, stream>>>(arg); break;
          case 4: multiBlasKernel<real, M, NXZ, 4><<<tp.grid, tp.block, tp.shared_bytes, stream>>>(arg); break;
#endif
          default: errorQuda("warp-split factor %d not instantiated", tp.aux.x);
          }

          tp.block.x /= tp.aux.x; // restore block size
#endif
        } else {
          errorQuda("Only implemented for GPU fields");
        }
      }

      void preTune()
      {
        for (int i = 0; i < NYW; ++i) {
          if (f.write.Y) y[i]->backup();
          if (f.write.W) w[i]->backup();
        }
      }

      void postTune()
      {
        for (int i = 0; i < NYW; ++i) {
          if (f.write.Y) y[i]->restore();
          if (f.write.W) w[i]->restore();
        }
      }

      bool advanceAux(TuneParam &param) const
      {
#ifdef WARP_SPLIT
        if (2 * param.aux.x <= max_warp_split) {
          param.aux.x *= 2;
          warp_split = param.aux.x;
          return true;
        } else {
          param.aux.x = 1;
          warp_split = param.aux.x;
          // reset the block dimension manually here to pick up the warp_split parameter
          resetBlockDim(param);
          return false;
        }
#else
        warp_split = 1;
        return false;
#endif
      }

      int blockStep() const { return deviceProp.warpSize / warp_split; }
      int blockMin() const { return deviceProp.warpSize / warp_split; }

      void initTuneParam(TuneParam &param) const
      {
        TunableVectorY::initTuneParam(param);
        param.grid.z = nParity;
        param.aux = make_int4(1, 0, 0, 0); // warp-split parameter
      }

      void defaultTuneParam(TuneParam &param) const
      {
        TunableVectorY::defaultTuneParam(param);
        param.grid.z = nParity;
        param.aux = make_int4(1, 0, 0, 0); // warp-split parameter
      }

      long long flops() const { return f.flops() * x[0]->Length(); }

      long long bytes() const
      {
        // the factor two here assumes we are reading and writing to the high precision vector
        return ((f.streams() - 2) * x[0]->Bytes() + 2 * y[0]->Bytes());
      }

      int tuningIter() const { return 3; }
    };

    template <template <typename ...> class Functor, typename store_t, typename y_store_t,
              int nSpin, typename T, int NXZ_>
    constexpr int MultiBlas<Functor, store_t, y_store_t, nSpin, T, NXZ_>::NXZ;

    template <int NXZ, template <typename ...> class Functor, typename T>
    void multiBlas(const coeff_array<T> &a, const coeff_array<T> &b, const coeff_array<T> &c,
                   CompositeColorSpinorField &x, CompositeColorSpinorField &y,
                   CompositeColorSpinorField &z, CompositeColorSpinorField &w)
    {
      instantiate<Functor, MultiBlas, true, NXZ>(a, b, c, *x[0], *y[0], x, y, z, w);
    }

    template <template <typename ...> class Functor, int n, typename T>
      typename std::enable_if<n!=1, void>::type
      multiBlas(const coeff_array<T> &a, const coeff_array<T> &b, const coeff_array<T> &c,
                CompositeColorSpinorField &x, CompositeColorSpinorField &y, CompositeColorSpinorField &z,
                CompositeColorSpinorField &w)
    {
      if (x.size() == n) multiBlas<n, Functor>(a, b, c, x, y, z, w);
      else multiBlas<Functor, n-1>(a, b, c, x, y, z, w);
    }

    template <template <typename ...> class Functor, int n, typename T>
      typename std::enable_if<n==1, void>::type
      multiBlas(const coeff_array<T> &a, const coeff_array<T> &b, const coeff_array<T> &c,
                CompositeColorSpinorField &x, CompositeColorSpinorField &y, CompositeColorSpinorField &z,
                CompositeColorSpinorField &w)
    {
      multiBlas<n, Functor>(a, b, c, x, y, z, w);
    }

    template <template <typename ...> class Functor, typename T>
    void multiBlas(const coeff_array<T> &a, const coeff_array<T> &b, const coeff_array<T> &c,
                   CompositeColorSpinorField &x, CompositeColorSpinorField &y, CompositeColorSpinorField &z,
                   CompositeColorSpinorField &w)
    {
      // instantiate the loop unrolling template
      switch (x.size()) {
      // by default all powers of two <= 128 are instantiated
      case 1: multiBlas<1, Functor>(a, b, c, x, y, z, w); break;
      case 2: multiBlas<2, Functor>(a, b, c, x, y, z, w); break;
      case 4: multiBlas<4, Functor>(a, b, c, x, y, z, w); break;
      case 8: multiBlas<8, Functor>(a, b, c, x, y, z, w); break;
      case 16: multiBlas<16, Functor>(a, b, c, x, y, z, w); break;
      case 32: multiBlas<32, Functor>(a, b, c, x, y, z, w); break;
      case 64: multiBlas<64, Functor>(a, b, c, x, y, z, w); break;
      case 128: multiBlas<128, Functor>(a, b, c, x, y, z, w); break;
      default:
        if (x.size() <= MAX_MULTI_BLAS_N) multiBlas<Functor, MAX_MULTI_BLAS_N>(a, b, c, x, y, z, w);
        else errorQuda("x.size %lu greater than MAX_MULTI_BLAS_N %d", x.size(), MAX_MULTI_BLAS_N);
      }
    }

    using range = std::pair<size_t,size_t>;

    template <template <typename...> class Functor, typename T>
    void axpy_recurse(const T *a_, std::vector<ColorSpinorField *> &x, std::vector<ColorSpinorField *> &y,
                      const range &range_x, const range &range_y, int upper, int coeff_width)
    {
      // if greater than max single-kernel size, recurse
      if (y.size() > (size_t)max_YW_size(x.size(), x[0]->Precision(), y[0]->Precision(), false, false, coeff_width, false)) {
        // We need to split up 'a' carefully since it's row-major.
        T *tmpmajor = new T[x.size() * y.size()];
        T *tmpmajor0 = &tmpmajor[0];
        T *tmpmajor1 = &tmpmajor[x.size() * (y.size() / 2)];
        std::vector<ColorSpinorField*> y0(y.begin(), y.begin() + y.size()/2);
        std::vector<ColorSpinorField*> y1(y.begin() + y.size()/2, y.end());

        const unsigned int xlen = x.size();
        const unsigned int ylen0 = y.size()/2;
        const unsigned int ylen1 = y.size() - y.size()/2;

        int count = 0, count0 = 0, count1 = 0;
        for (unsigned int i = 0; i < xlen; i++)
        {
          for (unsigned int j = 0; j < ylen0; j++)
            tmpmajor0[count0++] = a_[count++];
          for (unsigned int j = 0; j < ylen1; j++)
            tmpmajor1[count1++] = a_[count++];
        }

        axpy_recurse<Functor>(tmpmajor0, x, y0, range_x, range(range_y.first, range_y.first + y0.size()), upper, coeff_width);
        axpy_recurse<Functor>(tmpmajor1, x, y1, range_x, range(range_y.first + y0.size(), range_y.second), upper, coeff_width);

        delete[] tmpmajor;
      } else {
        // if at the bottom of recursion,
        if (is_valid_NXZ(x.size(), false, x[0]->Precision() < QUDA_SINGLE_PRECISION)) {
          // since tile range is [first,second), e.g., [first,second-1], we need >= here
          // if upper triangular and upper-right tile corner is below diagonal return
          if (upper == 1 && range_y.first >= range_x.second) { return; }
          // if lower triangular and lower-left tile corner is above diagonal return
          if (upper == -1 && range_x.first >= range_y.second) { return; }

          // mark true since we will copy the "a" matrix into constant memory
          coeff_array<T> a(a_), b, c;
          multiBlas<Functor>(a, b, c, x, y, x, y);
        } else {
          // split the problem in half and recurse
          const T *a0 = &a_[0];
          const T *a1 = &a_[(x.size() / 2) * y.size()];

          std::vector<ColorSpinorField *> x0(x.begin(), x.begin() + x.size() / 2);
          std::vector<ColorSpinorField *> x1(x.begin() + x.size() / 2, x.end());

          axpy_recurse<Functor>(a0, x0, y, range(range_x.first, range_x.first + x0.size()), range_y, upper, coeff_width);
          axpy_recurse<Functor>(a1, x1, y, range(range_x.first + x0.size(), range_x.second), range_y, upper, coeff_width);
        }
      } // end if (y.size() > max_YW_size())
    }

    void caxpy(const Complex *a_, std::vector<ColorSpinorField*> &x, std::vector<ColorSpinorField*> &y) {
      // Enter a recursion.
      // Pass a, x, y. (0,0) indexes the tiles. false specifies the matrix is unstructured.
      axpy_recurse<multicaxpy_>(a_, x, y, range(0,x.size()), range(0,y.size()), 0, 2);
    }

    void caxpy_U(const Complex *a_, std::vector<ColorSpinorField*> &x, std::vector<ColorSpinorField*> &y) {
      // Enter a recursion.
      // Pass a, x, y. (0,0) indexes the tiles. 1 indicates the matrix is upper-triangular,
      //                                         which lets us skip some tiles.
      if (x.size() != y.size())
      {
        errorQuda("An optimal block caxpy_U with non-square 'a' has not yet been implemented. Use block caxpy instead");
      }
      axpy_recurse<multicaxpy_>(a_, x, y, range(0,x.size()), range(0,y.size()), 1, 2);
    }

    void caxpy_L(const Complex *a_, std::vector<ColorSpinorField*> &x, std::vector<ColorSpinorField*> &y) {
      // Enter a recursion.
      // Pass a, x, y. (0,0) indexes the tiles. -1 indicates the matrix is lower-triangular
      //                                         which lets us skip some tiles.
      if (x.size() != y.size())
      {
        errorQuda("An optimal block caxpy_L with non-square 'a' has not yet been implemented. Use block caxpy instead");
      }
      axpy_recurse<multicaxpy_>(a_, x, y, range(0,x.size()), range(0,y.size()), -1, 2);
    }

    void caxpy(const Complex *a, ColorSpinorField &x, ColorSpinorField &y) { caxpy(a, x.Components(), y.Components()); }

    void caxpy_U(const Complex *a, ColorSpinorField &x, ColorSpinorField &y) { caxpy_U(a, x.Components(), y.Components()); }

    void caxpy_L(const Complex *a, ColorSpinorField &x, ColorSpinorField &y) { caxpy_L(a, x.Components(), y.Components()); }

    void caxpyz_recurse(const Complex *a_, std::vector<ColorSpinorField*> &x, std::vector<ColorSpinorField*> &y,
                        std::vector<ColorSpinorField*> &z, const range &range_x, const range &range_y,
                        int pass, int upper)
    {
      // if greater than max single-kernel size, recurse
      if (y.size() > (size_t)max_YW_size(x.size(), x[0]->Precision(), y[0]->Precision(), false, true, 2, false)) {
        // We need to split up 'a' carefully since it's row-major.
        Complex* tmpmajor = new Complex[x.size()*y.size()];
        Complex* tmpmajor0 = &tmpmajor[0];
        Complex* tmpmajor1 = &tmpmajor[x.size()*(y.size()/2)];
        std::vector<ColorSpinorField*> y0(y.begin(), y.begin() + y.size()/2);
        std::vector<ColorSpinorField*> y1(y.begin() + y.size()/2, y.end());

        std::vector<ColorSpinorField*> z0(z.begin(), z.begin() + z.size()/2);
        std::vector<ColorSpinorField*> z1(z.begin() + z.size()/2, z.end());

        const unsigned int xlen = x.size();
        const unsigned int ylen0 = y.size()/2;
        const unsigned int ylen1 = y.size() - y.size()/2;

        int count = 0, count0 = 0, count1 = 0;
        for (unsigned int i_ = 0; i_ < xlen; i_++)
        {
          for (unsigned int j = 0; j < ylen0; j++)
            tmpmajor0[count0++] = a_[count++];
          for (unsigned int j = 0; j < ylen1; j++)
            tmpmajor1[count1++] = a_[count++];
        }

        caxpyz_recurse(tmpmajor0, x, y0, z0, range_x, range(range_y.first, range_y.first + y0.size()), pass, upper);
        caxpyz_recurse(tmpmajor1, x, y1, z1, range_x, range(range_y.first + y0.size(), range_y.second), pass, upper);

        delete[] tmpmajor;
      } else {
        // if at bottom of recursion check where we are
        if (is_valid_NXZ(x.size(), false, x[0]->Precision() < QUDA_SINGLE_PRECISION)) {
          // check if tile straddles diagonal
          bool is_diagonal = (range_x.first < range_y.second) && (range_y.first < range_x.second);
          if (pass==1) {
            if (!is_diagonal) {
              // if upper triangular and upper-right tile corner is below diagonal return
              if (upper == 1 && range_y.first >= range_x.second) { return; }
              // if lower triangular and lower-left tile corner is above diagonal return
              if (upper == -1 && range_x.first >= range_y.second) { return; }
              caxpy(a_, x, z); return;  // off diagonal
            }
            return;
      	  } else {
            if (!is_diagonal) return; // We're on the first pass, so we only want to update the diagonal.
          }

          coeff_array<Complex> a(a_), b, c;
          multiBlas<multicaxpyz_>(a, b, c, x, y, x, z);
        } else {
          // split the problem in half and recurse
          const Complex *a0 = &a_[0];
          const Complex *a1 = &a_[(x.size() / 2) * y.size()];

          std::vector<ColorSpinorField *> x0(x.begin(), x.begin() + x.size() / 2);
          std::vector<ColorSpinorField *> x1(x.begin() + x.size() / 2, x.end());

          caxpyz_recurse(a0, x0, y, z, range(range_x.first, range_x.first + x0.size()), range_y, pass, upper);
          caxpyz_recurse(a1, x1, y, z, range(range_x.first + x0.size(), range_x.second), range_y, pass, upper);
        }
      } // end if (y.size() > max_YW_size())
    }

    void caxpyz(const Complex *a, std::vector<ColorSpinorField*> &x, std::vector<ColorSpinorField*> &y, std::vector<ColorSpinorField*> &z)
    {
      // first pass does the caxpyz on the diagonal
      caxpyz_recurse(a, x, y, z, range(0, x.size()), range(0, y.size()), 0, 0);
      // second pass does caxpy on the off diagonals
      caxpyz_recurse(a, x, y, z, range(0, x.size()), range(0, y.size()), 1, 0);
    }

    void caxpyz_U(const Complex *a, std::vector<ColorSpinorField*> &x, std::vector<ColorSpinorField*> &y, std::vector<ColorSpinorField*> &z)
    {
      // a is upper triangular.
      // first pass does the caxpyz on the diagonal
      caxpyz_recurse(a, x, y, z, range(0, x.size()), range(0, y.size()), 0, 1);
      // second pass does caxpy on the off diagonals
      caxpyz_recurse(a, x, y, z, range(0, x.size()), range(0, y.size()), 1, 1);
    }

    void caxpyz_L(const Complex *a, std::vector<ColorSpinorField*> &x, std::vector<ColorSpinorField*> &y, std::vector<ColorSpinorField*> &z)
    {
      // a is upper triangular.
      // first pass does the caxpyz on the diagonal
      caxpyz_recurse(a, x, y, z, range(0, x.size()), range(0, y.size()), 0, -1);
      // second pass does caxpy on the off diagonals
      caxpyz_recurse(a, x, y, z, range(0, x.size()), range(0, y.size()), 1, -1);
    }


    void caxpyz(const Complex *a, ColorSpinorField &x, ColorSpinorField &y, ColorSpinorField &z)
    {
      caxpyz(a, x.Components(), y.Components(), z.Components());
    }

    void caxpyz_U(const Complex *a, ColorSpinorField &x, ColorSpinorField &y, ColorSpinorField &z)
    {
      caxpyz_U(a, x.Components(), y.Components(), z.Components());
    }

    void caxpyz_L(const Complex *a, ColorSpinorField &x, ColorSpinorField &y, ColorSpinorField &z)
    {
      caxpyz_L(a, x.Components(), y.Components(), z.Components());
    }

    void axpyBzpcx(const double *a_, std::vector<ColorSpinorField *> &x_, std::vector<ColorSpinorField *> &y_,
                   const double *b_, ColorSpinorField &z_, const double *c_)
    {
      if (y_.size() <= (size_t)max_YW_size(1, z_.Precision(), y_[0]->Precision(), false, true, 1, false)) {
        // swizzle order since we are writing to x_ and y_, but the
	// multi-blas only allow writing to y and w, and moreover the
	// block width of y and w must match, and x and z must match.
	std::vector<ColorSpinorField*> &y = y_;
	std::vector<ColorSpinorField*> &w = x_;

	// wrap a container around the third solo vector
	std::vector<ColorSpinorField*> x;
	x.push_back(&z_);

        coeff_array<double> a(a_), b(b_), c(c_);
        multiBlas<1, multi_axpyBzpcx_>(a, b, c, x, y, x, w);
      } else {
        // split the problem in half and recurse
	const double *a0 = &a_[0];
	const double *b0 = &b_[0];
	const double *c0 = &c_[0];

	std::vector<ColorSpinorField*> x0(x_.begin(), x_.begin() + x_.size()/2);
	std::vector<ColorSpinorField*> y0(y_.begin(), y_.begin() + y_.size()/2);

	axpyBzpcx(a0, x0, y0, b0, z_, c0);

	const double *a1 = &a_[y_.size()/2];
	const double *b1 = &b_[y_.size()/2];
	const double *c1 = &c_[y_.size()/2];

	std::vector<ColorSpinorField*> x1(x_.begin() + x_.size()/2, x_.end());
	std::vector<ColorSpinorField*> y1(y_.begin() + y_.size()/2, y_.end());

	axpyBzpcx(a1, x1, y1, b1, z_, c1);
      }
    }

    void caxpyBxpz(const Complex *a_, std::vector<ColorSpinorField*> &x_, ColorSpinorField &y_,
		   const Complex *b_, ColorSpinorField &z_)
    {
      if (is_valid_NXZ(x_.size(), false, x_[0]->Precision() < QUDA_SINGLE_PRECISION)) // only split if we have to.
      {
        // swizzle order since we are writing to y_ and z_, but the
        // multi-blas only allow writing to y and w, and moreover the
        // block width of y and w must match, and x and z must match.
        // Also, wrap a container around them.
        std::vector<ColorSpinorField*> y;
        y.push_back(&y_);
        std::vector<ColorSpinorField*> w;
        w.push_back(&z_);

        // we're reading from x
        std::vector<ColorSpinorField*> &x = x_;

        coeff_array<Complex> a(a_), b(b_), c;
        multiBlas<multi_caxpyBxpz_>(a, b, c, x, y, x, w);
      } else {
        // split the problem in half and recurse
        const Complex *a0 = &a_[0];
        const Complex *b0 = &b_[0];

        std::vector<ColorSpinorField*> x0(x_.begin(), x_.begin() + x_.size()/2);

        caxpyBxpz(a0, x0, y_, b0, z_);

        const Complex *a1 = &a_[x_.size()/2];
        const Complex *b1 = &b_[x_.size()/2];

        std::vector<ColorSpinorField*> x1(x_.begin() + x_.size()/2, x_.end());

        caxpyBxpz(a1, x1, y_, b1, z_);
      }
    }

    void axpy(const double *a_, std::vector<ColorSpinorField*> &x, std::vector<ColorSpinorField*> &y)
    {
      // Enter a recursion.
      // Pass a, x, y. (0,0) indexes the tiles. false specifies the matrix is unstructured.
      axpy_recurse<multiaxpy_>(a_, x, y, range(0, x.size()), range(0, y.size()), 0, 1);
    }

    void axpy_U(const double *a_, std::vector<ColorSpinorField*> &x, std::vector<ColorSpinorField*> &y)
    {
      // Enter a recursion.
      // Pass a, x, y. (0,0) indexes the tiles. 1 indicates the matrix is upper-triangular,
      //                                         which lets us skip some tiles.
      if (x.size() != y.size())
      {
        errorQuda("An optimal block axpy_U with non-square 'a' has not yet been implemented. Use block axpy instead");
      }
      axpy_recurse<multiaxpy_>(a_, x, y, range(0, x.size()), range(0, y.size()), 1, 1);
    }

    void axpy_L(const double *a_, std::vector<ColorSpinorField*> &x, std::vector<ColorSpinorField*> &y)
    {
      // Enter a recursion.
      // Pass a, x, y. (0,0) indexes the tiles. -1 indicates the matrix is lower-triangular
      //                                         which lets us skip some tiles.
      if (x.size() != y.size())
      {
        errorQuda("An optimal block axpy_L with non-square 'a' has not yet been implemented. Use block axpy instead");
      }
      axpy_recurse<multiaxpy_>(a_, x, y, range(0, x.size()), range(0, y.size()), -1, 1);
    }

    // Composite field version
    void axpy(const double *a, ColorSpinorField &x, ColorSpinorField &y) { axpy(a, x.Components(), y.Components()); }

    void axpy_U(const double *a, ColorSpinorField &x, ColorSpinorField &y) { axpy_U(a, x.Components(), y.Components()); }

    void axpy_L(const double *a, ColorSpinorField &x, ColorSpinorField &y) { axpy_L(a, x.Components(), y.Components()); }

  } // namespace blas

} // namespace quda
