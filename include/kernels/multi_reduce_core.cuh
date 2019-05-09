#pragma once

#include <color_spinor_field_order.h>
#include <blas_helper.cuh>
#include <cub_helper.cuh>

//#define WARP_MULTI_REDUCE

namespace quda
{

  namespace blas
  {

#define BLAS_SPINOR // do not include ghost functions in Spinor class to reduce parameter space overhead
#include <texture.h>

    // storage for matrix coefficients
#define MAX_MATRIX_SIZE 4096
    static __constant__ signed char Amatrix_d[MAX_MATRIX_SIZE];
    static __constant__ signed char Bmatrix_d[MAX_MATRIX_SIZE];
    static __constant__ signed char Cmatrix_d[MAX_MATRIX_SIZE];

    static signed char *Amatrix_h;
    static signed char *Bmatrix_h;
    static signed char *Cmatrix_h;

    /**
       @brief Parameter struct for generic multi-blas kernel.
       @tparam NXZ is dimension of input vectors: X,Z,V
       @tparam NYW is dimension of in-output vectors: Y,W
       @tparam SpinorX Type of input spinor for x argument
       @tparam SpinorY Type of input spinor for y argument
       @tparam SpinorZ Type of input spinor for z argument
       @tparam SpinorW Type of input spinor for w argument
       @tparam SpinorW Type of input spinor for v argument
       @tparam Reducer Functor used to operate on data
    */
    template <int NXZ, typename ReduceType, typename SpinorX, typename SpinorY, typename SpinorZ, typename SpinorW,
        typename Reducer>
    struct MultiReduceArg : public ReduceArg<vector_type<ReduceType, NXZ>> {

      const int NYW;
      SpinorX X[NXZ];
      SpinorY Y[MAX_MULTI_BLAS_N];
      SpinorZ Z[NXZ];
      SpinorW W[MAX_MULTI_BLAS_N];
      Reducer r;
      const int length;
      MultiReduceArg(SpinorX X[NXZ], SpinorY Y[], SpinorZ Z[NXZ], SpinorW W[], Reducer r, int NYW, int length) :
          NYW(NYW),
          r(r),
          length(length)
      {
        for (int i = 0; i < NXZ; ++i) {
          this->X[i] = X[i];
          this->Z[i] = Z[i];
        }

        for (int i = 0; i < NYW; ++i) {
          this->Y[i] = Y[i];
          this->W[i] = W[i];
        }
      }
    };

    // 'sum' should be an array of length NXZ...?
    template <int k, int NXZ, typename FloatN, int M, typename ReduceType, typename Arg>
    __device__ inline void compute(vector_type<ReduceType, NXZ> &sum, Arg &arg, int idx, int parity)
    {

      constexpr int kmod = k;
      // there's an old warning about silencing an out-of-bounds compiler warning,
      // but I never seem to get it, and I'd need to compare against NYW anyway,
      // which we can't really get at here b/c it's not a const, and I don't want
      // to fix that. It works fine based on the switch in the function below.

      while (idx < arg.length) {

        FloatN x[M], y[M], z[M], w[M];

        arg.Y[kmod].load(y, idx, parity);
        arg.W[kmod].load(w, idx, parity);

        // Each NYW owns its own thread.
        // The NXZ's are all in the same thread block,
        // so they can share the same memory.
#pragma unroll
        for (int l = 0; l < NXZ; l++) {
          arg.X[l].load(x, idx, parity);
          arg.Z[l].load(z, idx, parity);

          arg.r.pre();

#pragma unroll
          for (int j = 0; j < M; j++) arg.r(sum[l], x[j], y[j], z[j], w[j], k, l);

          arg.r.post(sum[l]);
        }

        arg.Y[kmod].save(y, idx, parity);
        arg.W[kmod].save(w, idx, parity);

        idx += gridDim.x * blockDim.x;
      }
    }

#ifdef WARP_MULTI_REDUCE
    template <typename ReduceType, typename FloatN, int M, int NXZ, typename Arg>
#else
    template <int block_size, typename ReduceType, typename FloatN, int M, int NXZ, typename Arg>
#endif
    __global__ void multiReduceKernel(Arg arg)
    {
      unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
      unsigned int k = blockIdx.y * blockDim.y + threadIdx.y;
      unsigned int parity = blockIdx.z;

      if (k >= arg.NYW) return; // safe since k are different thread blocks

      vector_type<ReduceType, NXZ> sum;

      switch (k) {
      case 0: compute<0, NXZ, FloatN, M, ReduceType>(sum, arg, i, parity); break;
#if MAX_MULTI_BLAS_N >= 2
      case 1: compute<1, NXZ, FloatN, M, ReduceType>(sum, arg, i, parity); break;
#if MAX_MULTI_BLAS_N >= 3
      case 2: compute<2, NXZ, FloatN, M, ReduceType>(sum, arg, i, parity); break;
#if MAX_MULTI_BLAS_N >= 4
      case 3: compute<3, NXZ, FloatN, M, ReduceType>(sum, arg, i, parity); break;
#if MAX_MULTI_BLAS_N >= 5
      case 4: compute<4, NXZ, FloatN, M, ReduceType>(sum, arg, i, parity); break;
#if MAX_MULTI_BLAS_N >= 6
      case 5: compute<5, NXZ, FloatN, M, ReduceType>(sum, arg, i, parity); break;
#if MAX_MULTI_BLAS_N >= 7
      case 6: compute<6, NXZ, FloatN, M, ReduceType>(sum, arg, i, parity); break;
#if MAX_MULTI_BLAS_N >= 8
      case 7: compute<7, NXZ, FloatN, M, ReduceType>(sum, arg, i, parity); break;
#if MAX_MULTI_BLAS_N >= 9
      case 8: compute<8, NXZ, FloatN, M, ReduceType>(sum, arg, i, parity); break;
#if MAX_MULTI_BLAS_N >= 10
      case 9: compute<9, NXZ, FloatN, M, ReduceType>(sum, arg, i, parity); break;
#if MAX_MULTI_BLAS_N >= 11
      case 10: compute<10, NXZ, FloatN, M, ReduceType>(sum, arg, i, parity); break;
#if MAX_MULTI_BLAS_N >= 12
      case 11: compute<11, NXZ, FloatN, M, ReduceType>(sum, arg, i, parity); break;
#if MAX_MULTI_BLAS_N >= 13
      case 12: compute<12, NXZ, FloatN, M, ReduceType>(sum, arg, i, parity); break;
#if MAX_MULTI_BLAS_N >= 14
      case 13: compute<13, NXZ, FloatN, M, ReduceType>(sum, arg, i, parity); break;
#if MAX_MULTI_BLAS_N >= 15
      case 14: compute<14, NXZ, FloatN, M, ReduceType>(sum, arg, i, parity); break;
#if MAX_MULTI_BLAS_N >= 16
      case 15: compute<15, NXZ, FloatN, M, ReduceType>(sum, arg, i, parity); break;
#endif // 16
#endif // 15
#endif // 14
#endif // 13
#endif // 12
#endif // 11
#endif // 10
#endif // 9
#endif // 8
#endif // 7
#endif // 6
#endif // 5
#endif // 4
#endif // 3
#endif // 2
      }

#ifdef WARP_MULTI_REDUCE
      ::quda::warp_reduce<vector_type<ReduceType, NXZ>>(arg, sum, arg.NYW * parity + k);
#else
      ::quda::reduce<block_size, vector_type<ReduceType, NXZ>>(arg, sum, arg.NYW * parity + k);
#endif

    } // multiReduceKernel

    template <typename T> struct coeff_array {
      const T *data;
      const bool use_const;
      coeff_array() : data(nullptr), use_const(false) {}
      coeff_array(const T *data, bool use_const) : data(data), use_const(use_const) {}
    };

    /**
       Base class from which all reduction functors should derive.
    */
    template <int NXZ, typename ReduceType, typename Float2, typename FloatN> struct MultiReduceFunctor {

      //! pre-computation routine called before the "M-loop"
      virtual __device__ __host__ void pre() { ; }

      //! where the reduction is usually computed and any auxiliary operations
      virtual __device__ __host__ __host__ void operator()(
          ReduceType &sum, FloatN &x, FloatN &y, FloatN &z, FloatN &w, const int i, const int j)
          = 0;

      //! post-computation routine called after the "M-loop"
      virtual __device__ __host__ void post(ReduceType &sum) { ; }
    };

    /**
       Return the real dot product of x and y
       Broken at the moment---need to update reDotProduct with permuting, etc of cDotProduct below.
    */
    template <typename ReduceType> __device__ __host__ void dot_(ReduceType &sum, const double2 &a, const double2 &b)
    {
      sum += (ReduceType)a.x * (ReduceType)b.x;
      sum += (ReduceType)a.y * (ReduceType)b.y;
    }

    template <typename ReduceType> __device__ __host__ void dot_(ReduceType &sum, const float2 &a, const float2 &b)
    {
      sum += (ReduceType)a.x * (ReduceType)b.x;
      sum += (ReduceType)a.y * (ReduceType)b.y;
    }

    template <typename ReduceType> __device__ __host__ void dot_(ReduceType &sum, const float4 &a, const float4 &b)
    {
      sum += (ReduceType)a.x * (ReduceType)b.x;
      sum += (ReduceType)a.y * (ReduceType)b.y;
      sum += (ReduceType)a.z * (ReduceType)b.z;
      sum += (ReduceType)a.w * (ReduceType)b.w;
    }

    template <int NXZ, typename ReduceType, typename Float2, typename FloatN>
    struct Dot : public MultiReduceFunctor<NXZ, ReduceType, Float2, FloatN> {
      typedef typename scalar<Float2>::type real;
      const int NYW;
      Dot(const coeff_array<Complex> &a, const coeff_array<Complex> &b, const coeff_array<Complex> &c, int NYW) :
          NYW(NYW)
      {
        ;
      }
      __device__ __host__ void operator()(
          ReduceType &sum, FloatN &x, FloatN &y, FloatN &z, FloatN &w, const int i, const int j)
      {
        dot_<ReduceType>(sum, x, y);
      }
      static int streams() { return 2; } //! total number of input and output streams
      static int flops() { return 2; }   //! flops per element
    };

    /**
       Returns complex-valued dot product of x and y
    */
    template <typename ReduceType> __device__ __host__ void cdot_(ReduceType &sum, const double2 &a, const double2 &b)
    {
      typedef typename scalar<ReduceType>::type scalar;
      sum.x += (scalar)a.x * (scalar)b.x;
      sum.x += (scalar)a.y * (scalar)b.y;
      sum.y += (scalar)a.x * (scalar)b.y;
      sum.y -= (scalar)a.y * (scalar)b.x;
    }

    template <typename ReduceType> __device__ __host__ void cdot_(ReduceType &sum, const float2 &a, const float2 &b)
    {
      typedef typename scalar<ReduceType>::type scalar;
      sum.x += (scalar)a.x * (scalar)b.x;
      sum.x += (scalar)a.y * (scalar)b.y;
      sum.y += (scalar)a.x * (scalar)b.y;
      sum.y -= (scalar)a.y * (scalar)b.x;
    }

    template <typename ReduceType> __device__ __host__ void cdot_(ReduceType &sum, const float4 &a, const float4 &b)
    {
      typedef typename scalar<ReduceType>::type scalar;
      sum.x += (scalar)a.x * (scalar)b.x;
      sum.x += (scalar)a.y * (scalar)b.y;
      sum.x += (scalar)a.z * (scalar)b.z;
      sum.x += (scalar)a.w * (scalar)b.w;
      sum.y += (scalar)a.x * (scalar)b.y;
      sum.y -= (scalar)a.y * (scalar)b.x;
      sum.y += (scalar)a.z * (scalar)b.w;
      sum.y -= (scalar)a.w * (scalar)b.z;
    }

    template <int NXZ, typename ReduceType, typename Float2, typename FloatN>
    struct Cdot : public MultiReduceFunctor<NXZ, ReduceType, Float2, FloatN> {
      typedef typename scalar<Float2>::type real;
      const int NYW;
      Cdot(const coeff_array<Complex> &a, const coeff_array<Complex> &b, const coeff_array<Complex> &c, int NYW) :
          NYW(NYW)
      {
        ;
      }
      __device__ __host__ inline void operator()(
          ReduceType &sum, FloatN &x, FloatN &y, FloatN &z, FloatN &w, const int i, const int j)
      {
        cdot_<ReduceType>(sum, x, y);
      }
      static int streams() { return 2; } //! total number of input and output streams
      static int flops() { return 4; }   //! flops per element
    };

    template <int NXZ, typename ReduceType, typename Float2, typename FloatN>
    struct CdotCopy : public MultiReduceFunctor<NXZ, ReduceType, Float2, FloatN> {
      typedef typename scalar<Float2>::type real;
      const int NYW;
      CdotCopy(const coeff_array<Complex> &a, const coeff_array<Complex> &b, const coeff_array<Complex> &c, int NYW) :
          NYW(NYW)
      {
        ;
      }
      __device__ __host__ inline void operator()(
          ReduceType &sum, FloatN &x, FloatN &y, FloatN &z, FloatN &w, const int i, const int j)
      {
        cdot_<ReduceType>(sum, x, y);
        if (i == j) w = y;
      }
      static int streams() { return 2; } //! total number of input and output streams
      static int flops() { return 4; }   //! flops per element
    };

  } // namespace blas

} // namespace quda
