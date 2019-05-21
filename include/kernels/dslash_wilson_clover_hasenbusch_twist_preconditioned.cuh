#pragma once

#include <kernels/dslash_wilson.cuh>
#include <linalg.cuh>

namespace quda {

  template <typename Float, int nColor, QudaReconstructType reconstruct_, bool dynamic_clover_>
  struct WilsonCloverHasenbuschTwistArg : WilsonArg<Float,nColor,reconstruct_> {
    using WilsonArg<Float,nColor,reconstruct_>::nSpin;
    static constexpr int length = (nSpin / (nSpin/2)) * 2 * nColor * nColor * (nSpin/2) * (nSpin/2) / 2;
    static constexpr bool dynamic_clover = dynamic_clover_;

    typedef typename clover_mapper<Float,length>::type C;
    typedef typename mapper<Float>::type real;

    const C A;
    const C A_inv;
    real b;

    WilsonCloverHasenbuschTwistArg(ColorSpinorField &out, const ColorSpinorField &in, const GaugeField &U,
		    const CloverField &A_, double kappa_, double b_, const ColorSpinorField &x,
		    int parity, bool dagger, const int *comm_override)
      : WilsonArg<Float,nColor,reconstruct_>(out, in, U, kappa_, x, parity, dagger, comm_override),
	A(A_,false), A_inv(A_, dynamic_clover ? false : true), b(dagger ? -0.5*b_ : 0.5*b_) // if dynamic clover we don't want the inverse field
    { }
  };

  /**
     @brief Apply the clover preconditioned Wilson dslash
     - no xpay: out(x) = M*in = A(x)^{-1}D * in(x-mu)
     - with xpay:  out(x) = M*in = (1 - kappa*A(x)^{-1}D) * in(x-mu)
  */
  template <typename Float, int nDim, int nColor, int nParity, bool dagger, bool xpay, KernelType kernel_type, bool doClovInv, typename Arg>
  __device__ __host__ inline void wilsonCloverHasenbuschTwist(Arg &arg, int idx, int parity)
  {

	  using namespace linalg; // for Cholesky
	  typedef typename mapper<Float>::type real;
	  typedef ColorSpinor<real,nColor,4> Vector;
	  typedef ColorSpinor<real,nColor,2> HalfVector;

	  bool active = kernel_type == EXTERIOR_KERNEL_ALL ? false : true; // is thread active (non-trival for fused kernel only)
	  int thread_dim; // which dimension is thread working on (fused kernel only)
	  int coord[nDim];
	  int x_cb = getCoords<nDim,QUDA_4D_PC,kernel_type>(coord, arg, idx, parity, thread_dim);

	  const int my_spinor_parity = nParity == 2 ? parity : 0;

	  Vector out;

	  // defined in dslash_wilson.cuh
	  applyWilson<Float,nDim,nColor,nParity,dagger,kernel_type>(out, arg, coord, x_cb, 0, parity, idx, thread_dim, active);

	  if (kernel_type != INTERIOR_KERNEL && active) {
		  // if we're not the interior kernel, then we must sum the partial
		  Vector x = arg.out(x_cb, my_spinor_parity);
		  out += x;
	  }

	  if ( isComplete<kernel_type>(arg, coord) && active ) {

		  if ( ! doClovInv ) {

			  Vector x = arg.x(x_cb, my_spinor_parity);
			  out = x + arg.kappa * out ;
		  }
		  else {
			  out.toRel(); // switch to chiral basis

			  Vector tmp;

#pragma unroll
			  for (int chirality=0; chirality<2; chirality++) {

				  HMatrix<real,nColor*Arg::nSpin/2> A_inv = arg.A_inv(x_cb, parity, chirality);
				  HalfVector chi = out.chiral_project(chirality);

				  if (arg.dynamic_clover) {
					  Cholesky<HMatrix,real,nColor*Arg::nSpin/2> cholesky(A_inv);
					  chi = static_cast<real>(0.25)*cholesky.backward(cholesky.forward(chi));
				  } else {
					  chi = A_inv * chi;
				  }

				  tmp += chi.chiral_reconstruct(chirality);
			  }

			  tmp.toNonRel(); // switch back to non-chiral basis
			  Vector x = arg.x(x_cb, my_spinor_parity);
			  out = x + arg.kappa * tmp;
		  }

		  // At this point: out = x + k A^{-1} D in or out = x + k D in
		  //
		  // now we must add on i g_5 b A x
		  {
			  Vector x = arg.x(x_cb, my_spinor_parity);
			  x.toRel();
			  Vector tmp;
#pragma unroll
			  for (int chirality=0; chirality<2; chirality++) {

				  HMatrix<real,nColor*Arg::nSpin/2> A = arg.A(x_cb, parity, chirality);
			  	  HalfVector x_chi = x.chiral_project(chirality);
			  	  HalfVector Ax_chi = A*x_chi;
			  	  const complex<real> b(0.0, chirality == 0 ? static_cast<real>(arg.b) : -static_cast<real>(arg.b) );
			  	  x_chi = b*Ax_chi;
			  	  tmp += x_chi.chiral_reconstruct(chirality);

			  }
			  tmp.toNonRel(); // switch back to non-chiral basis
			  out += tmp;

		  }
	  }

	  if (kernel_type != EXTERIOR_KERNEL_ALL || active) arg.out(x_cb, my_spinor_parity) = out;
  }


  // CPU kernel for applying the Wilson operator to a vector
  template <typename Float, int nDim, int nColor, int nParity, bool dagger, bool xpay, KernelType kernel_type, typename Arg>
  void wilsonCloverHasenbuschTwistNoClovInvCPU(Arg arg)
  {

    for (int parity= 0; parity < nParity; parity++) {
      // for full fields then set parity from loop else use arg setting
      parity = nParity == 2 ? parity : arg.parity;

      for (int x_cb = 0; x_cb < arg.threads; x_cb++) { // 4-d volume
    	  wilsonCloverHasenbuschTwist<Float,nDim,nColor,nParity,dagger,xpay,kernel_type,false>(arg, x_cb, parity);
      } // 4-d volumeCB
    } // parity

  }

  // GPU Kernel for applying the Wilson operator to a vector
  template <typename Float, int nDim, int nColor, int nParity, bool dagger, bool xpay, KernelType kernel_type, typename Arg>
  __global__ void wilsonCloverHasenbuschTwistNoClovInvGPU(Arg arg)
  {
    int x_cb = blockIdx.x*blockDim.x + threadIdx.x;
    if (x_cb >= arg.threads) return;

    // for full fields set parity from y thread index else use arg setting
    int parity = nParity == 2 ? blockDim.z*blockIdx.z + threadIdx.z : arg.parity;

    switch(parity) {
    case 0: wilsonCloverHasenbuschTwist<Float,nDim,nColor,nParity,dagger,xpay,kernel_type,false>(arg, x_cb, 0); break;
    case 1: wilsonCloverHasenbuschTwist<Float,nDim,nColor,nParity,dagger,xpay,kernel_type,false>(arg, x_cb, 1); break;
    }

  }

  // CPU kernel for applying the Wilson operator to a vector
   template <typename Float, int nDim, int nColor, int nParity, bool dagger, bool xpay,
   	   KernelType kernel_type, typename Arg>
   void wilsonCloverHasenbuschTwistClovInvCPU(Arg arg)
   {

     for (int parity= 0; parity < nParity; parity++) {
       // for full fields then set parity from loop else use arg setting
       parity = nParity == 2 ? parity : arg.parity;

       for (int x_cb = 0; x_cb < arg.threads; x_cb++) { // 4-d volume
    	   wilsonCloverHasenbuschTwist<Float,nDim,nColor,nParity,dagger,xpay,kernel_type,true>(arg, x_cb, parity);
       } // 4-d volumeCB
     } // parity

   }

   // GPU Kernel for applying the Wilson operator to a vector
   template <typename Float, int nDim, int nColor, int nParity, bool dagger, bool xpay, KernelType kernel_type, typename Arg>
   __global__ void wilsonCloverHasenbuschTwistClovInvGPU(Arg arg)
   {
     int x_cb = blockIdx.x*blockDim.x + threadIdx.x;
     if (x_cb >= arg.threads) return;

     // for full fields set parity from y thread index else use arg setting
     int parity = nParity == 2 ? blockDim.z*blockIdx.z + threadIdx.z : arg.parity;

     switch(parity) {
     case 0: wilsonCloverHasenbuschTwist<Float,nDim,nColor,nParity,dagger,xpay,kernel_type,true>(arg, x_cb, 0); break;
     case 1: wilsonCloverHasenbuschTwist<Float,nDim,nColor,nParity,dagger,xpay,kernel_type,true>(arg, x_cb, 1); break;
     }

   }
} // namespace quda
