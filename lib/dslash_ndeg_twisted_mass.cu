#include <gauge_field.h>
#include <color_spinor_field.h>
#include <dslash.h>
#include <worker.h>

#include <dslash_policy.cuh>
#include <kernels/dslash_ndeg_twisted_mass.cuh>

/**
   This is the gauged twisted-mass operator acting on a non-generate
   quark doublet.
*/

namespace quda
{

  template <typename Float, int nDim, int nColor, typename Arg> class NdegTwistedMass : public Dslash<nDegTwistedMass,Float,Arg>
  {
    using Dslash = Dslash<nDegTwistedMass,Float,Arg>;
    using Dslash::arg;
    using Dslash::in;

public:
    NdegTwistedMass(Arg &arg, const ColorSpinorField &out, const ColorSpinorField &in) :
      Dslash(arg, out, in)
    {
      TunableVectorYZ::resizeVector(2, arg.nParity);
    }

    virtual ~NdegTwistedMass() {}

    void apply(const cudaStream_t &stream)
    {
      TuneParam tp = tuneLaunch(*this, getTuning(), getVerbosity());
      Dslash::setParam(tp);
      if (arg.xpay) Dslash::template instantiate<packShmem, nDim, true>(tp, stream);
      else          errorQuda("Non-degenerate twisted-mass operator only defined for xpay=true");
    }

    long long flops() const
    {
      long long flops = Dslash::flops();
      switch (arg.kernel_type) {
      case INTERIOR_KERNEL:
      case KERNEL_POLICY:
        flops += 2 * nColor * 4 * 4 * in.Volume(); // complex * Nc * Ns * fma * vol
        break;
      default: break; // twisted-mass flops are in the interior kernel
      }
      return flops;
    }
  };

  template <typename Float, int nColor, QudaReconstructType recon> struct NdegTwistedMassApply {

    inline NdegTwistedMassApply(ColorSpinorField &out, const ColorSpinorField &in, const GaugeField &U, double a,
                                double b, double c, const ColorSpinorField &x, int parity, bool dagger,
                                const int *comm_override, TimeProfile &profile)
    {
      constexpr int nDim = 4;
      NdegTwistedMassArg<Float, nColor, recon> arg(out, in, U, a, b, c, x, parity, dagger, comm_override);
      NdegTwistedMass<Float, nDim, nColor, NdegTwistedMassArg<Float, nColor, recon>> twisted(arg, out, in);

      dslash::DslashPolicyTune<decltype(twisted)> policy(
        twisted, const_cast<cudaColorSpinorField *>(static_cast<const cudaColorSpinorField *>(&in)),
        in.getDslashConstant().volume_4d_cb, in.getDslashConstant().ghostFaceCB, profile);
      policy.apply(0);

      checkCudaError();
    }
  };

  void ApplyNdegTwistedMass(ColorSpinorField &out, const ColorSpinorField &in, const GaugeField &U, double a, double b,
                            double c, const ColorSpinorField &x, int parity, bool dagger, const int *comm_override,
                            TimeProfile &profile)
  {
#ifdef GPU_NDEG_TWISTED_MASS_DIRAC
    if (in.V() == out.V()) errorQuda("Aliasing pointers");
    if (in.FieldOrder() != out.FieldOrder())
      errorQuda("Field order mismatch in = %d, out = %d", in.FieldOrder(), out.FieldOrder());

    // check all precisions match
    checkPrecision(out, in, x, U);

    // check all locations match
    checkLocation(out, in, x, U);

    instantiate<NdegTwistedMassApply>(out, in, U, a, b, c, x, parity, dagger, comm_override, profile);
#else
    errorQuda("Non-degenerate twisted-mass dslash has not been built");
#endif // GPU_NDEG_TWISTED_MASS_DIRAC
  }

} // namespace quda
