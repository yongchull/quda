###### Local configuration:

CUDA_INSTALL_PATH = /usr/local/cuda
QDP_INSTALL_PATH = 
QDPXX_CXXFLAGS = 
QDPXX_LDFLAGS = 
QDPXX_LIBS = 

CPU_ARCH = x86_64  	  # x86 or x86_64
GPU_ARCH = sm_35	  # sm_11, sm_12, sm_13, sm_20, sm_21, sm_30, or sm_35
OS       = linux	  # linux or osx

PYTHON = python	  # python 2.5 or later required for 'make gen'

# compilation options
HOST_DEBUG = yes		# compile host debug code
DEVICE_DEBUG = no		# compile device debug code for cuda-gdb 
VERBOSE = no			# display kernel register useage
BLAS_TEX = yes			# enable texture reads in BLAS?
FERMI_DBLE_TEX = yes		# enable double-precision texture reads on Fermi?

BUILD_WILSON_DIRAC = no			# build Wilson Dirac operators?
BUILD_CLOVER_DIRAC = no			# build clover Dirac operators?
BUILD_DOMAIN_WALL_DIRAC = no			# build domain wall Dirac operators?
BUILD_STAGGERED_DIRAC = yes			# build staggered Dirac operators?
BUILD_TWISTED_MASS_DIRAC = no		# build twisted mass Dirac operators?
BUILD_NDEG_TWISTED_MASS_DIRAC = no	# build non-degenerate twisted mass Dirac operators?
BUILD_FATLINK = no			# build code for computing asqtad fat links?
BUILD_HISQLINK = yes			# build code for computing hisq fat links?
BUILD_GAUGE_FORCE = no			# build code for (1-loop Symanzik) gauge force?
BUILD_FERMION_FORCE = no		# build code for asqtad fermion force?
BUILD_HISQ_FORCE = no			# build code for hisq fermion force?

# Multi-GPU options
BUILD_MULTI_GPU = yes  # set to 'yes' to build the multi-GPU code
BUILD_QMP = no              # set to 'yes' to build the QMP multi-GPU code
BUILD_MPI = yes              # set to 'yes' to build the MPI multi-GPU code

# GPUdirect options
GPU_DIRECT = yes            # set to 'yes' to allow GPU and NIC to shared pinned buffers

# Interface options
BUILD_QDP_INTERFACE = yes                     # build qdp interface
BUILD_MILC_INTERFACE = yes                   # build milc interface
BUILD_CPS_INTERFACE = no                     # build cps interface
BUILD_QDPJIT_INTERFACE = no               # build qdpjit interface
BUILD_BQCD_INTERFACE = no                   # build bqcd interface

# Packing option
DEVICE_PACK = no	     # set to 'yes' to enable packing and unpacking on the device

BUILD_QIO = no    # set to 'yes' to build QIO code for binary I/O

USE_QDPJIT = no  # build QDP-JIT support?

FECC = /uufs/chpc.utah.edu/sys/pkg/mpich2/3.0.4/bin/mpicc			# front-end CC
FECXX = /uufs/chpc.utah.edu/sys/pkg/mpich2/3.0.4/bin/mpicxx			# front-end CXX
FEF90 = 			# front-end F90

MPI_HOME=/uufs/chpc.utah.edu/sys/pkg/mpich2/3.0.4
QMP_HOME=
QIO_HOME=

NUMA_AFFINITY=yes   # enable NUMA affinity?

######

INC = -I$(CUDA_INSTALL_PATH)/include

ifeq ($(strip $(CPU_ARCH)), x86_64)
  ifeq ($(strip $(OS)), osx)
    LIB = -L$(CUDA_INSTALL_PATH)/lib -lcudart
    NVCCOPT = -m64
  else
    LIB = -L$(CUDA_INSTALL_PATH)/lib64 -lcudart
  endif
else
  LIB = -L$(CUDA_INSTALL_PATH)/lib -lcudart -m32
  COPT = -malign-double -m32
  NVCCOPT = -m32
endif

COMP_CAP = $(GPU_ARCH:sm_%=%0)

COPT += -D__COMPUTE_CAPABILITY__=$(COMP_CAP)
NVCCOPT += -D__COMPUTE_CAPABILITY__=$(COMP_CAP)

TESLA_ARCH = $(shell [ $(COMP_CAP) -lt 200 ] && echo true)
ifneq ($(TESLA_ARCH),true)
  NVCCOPT += -ftz=true -prec-div=false -prec-sqrt=false
endif

ifeq ($(strip $(BUILD_MULTI_GPU)), yes)
  COPT += -DMULTI_GPU
  NVCCOPT += -DMULTI_GPU
else
  COMM_OBJS = comm_single.o
endif

CC  = $(FECC)
CXX = $(FECXX)
F90 = $(FEF90)

ifeq ($(strip $(BUILD_MPI)), yes)
  MPI_CFLAGS =
  MPI_LDFLAGS =
  MPI_LIBS =
  INC += -DMPI_COMMS $(MPI_CFLAGS) -I$(MPI_HOME)/include/mpi
  LIB += $(MPI_LDFLAGS) $(MPI_LIBS)
  COMM_OBJS = comm_mpi.o
endif

ifeq ($(strip $(BUILD_QMP)), yes)
  QMP_CFLAGS = $(shell $(QMP_HOME)/bin/qmp-config --cflags )
  QMP_LDFLAGS = $(shell $(QMP_HOME)/bin/qmp-config --ldflags )
  QMP_LIBS = $(shell $(QMP_HOME)/bin/qmp-config --libs )
  INC += -DQMP_COMMS $(QMP_CFLAGS)
  LIB += $(QMP_LDFLAGS) $(QMP_LIBS)
  COMM_OBJS = comm_qmp.o
endif 

ifeq ($(strip $(BUILD_QIO)), yes)
  INC += -DHAVE_QIO -I$(QIO_HOME)/include
  LIB += -L$(QIO_HOME)/lib -lqio -llime
  QIO_UTIL = qio_util.o layout_hyper.o gauge_qio.o
endif

ifeq ($(strip $(BUILD_WILSON_DIRAC)), yes)
  NVCCOPT += -DGPU_WILSON_DIRAC
  COPT += -DGPU_WILSON_DIRAC
  DIRAC_TEST = dslash_test invert_test
endif

ifeq ($(strip $(BUILD_DOMAIN_WALL_DIRAC)), yes)
  NVCCOPT += -DGPU_DOMAIN_WALL_DIRAC
  COPT += -DGPU_DOMAIN_WALL_DIRAC
  DIRAC_TEST = dslash_test invert_test
endif

ifeq ($(strip $(BUILD_STAGGERED_DIRAC)), yes)
  NVCCOPT += -DGPU_STAGGERED_DIRAC
  COPT += -DGPU_STAGGERED_DIRAC
  STAGGERED_DIRAC_TEST=staggered_dslash_test staggered_invert_test
endif

ifeq ($(strip $(BUILD_CLOVER_DIRAC)), yes)
  NVCCOPT += -DGPU_CLOVER_DIRAC -DGPU_WILSON_DIRAC
  COPT += -DGPU_CLOVER_DIRAC -DGPU_WILSON_DIRAC
endif

ifeq ($(strip $(BUILD_TWISTED_MASS_DIRAC)), yes)
  NVCCOPT += -DGPU_TWISTED_MASS_DIRAC -DGPU_WILSON_DIRAC
  COPT += -DGPU_TWISTED_MASS_DIRAC -DGPU_WILSON_DIRAC
endif

ifeq ($(strip $(BUILD_NDEG_TWISTED_MASS_DIRAC)), yes)
  NVCCOPT += -DGPU_NDEG_TWISTED_MASS_DIRAC -DGPU_TWISTED_MASS_DIRAC -DGPU_WILSON_DIRAC
  COPT += -DGPU_NDEG_TWISTED_MASS_DIRAC -DGPU_TWISTED_MASS_DIRAC -DGPU_WILSON_DIRAC
endif

ifeq ($(strip $(BUILD_FATLINK)), yes)
  NVCCOPT += -DGPU_FATLINK
  FATLINK_TEST=llfat_test
  COPT += -DGPU_FATLINK
endif

ifeq ($(strip $(BUILD_HISQLINK)), yes)
  ifneq ($(strip $(BUILD_FATLINK)), yes) 
    NVCCOPT += -DGPU_FATLINK
    COPT    += -DGPU_FATLINK
    FATLINK_TEST=llfat_test
  endif
  UNITARIZE_LINK_TEST=unitarize_link_test
  NVCCOPT += -DGPU_UNITARIZE
  COPT    += -DGPU_UNITARIZE
endif

ifeq ($(strip $(BUILD_GAUGE_FORCE)), yes)
  NVCCOPT += -DGPU_GAUGE_FORCE
  COPT += -DGPU_GAUGE_FORCE
  GAUGE_FORCE_TEST=gauge_force_test
endif

ifeq ($(strip $(BUILD_FERMION_FORCE)), yes)
  NVCCOPT += -DGPU_FERMION_FORCE
  COPT += -DGPU_FERMION_FORCE
  FERMION_FORCE_TEST=fermion_force_test
endif

ifeq ($(strip $(BUILD_HISQ_FORCE)), yes)
  NVCCOPT += -DGPU_HISQ_FORCE
  COPT += -DGPU_HISQ_FORCE
  HISQ_PATHS_FORCE_TEST=hisq_paths_force_test
  HISQ_UNITARIZE_FORCE_TEST=hisq_unitarize_force_test
endif

ifeq ($(strip $(HOST_DEBUG)), yes)
  NVCCOPT += -g -DHOST_DEBUG
  COPT += -g -fno-inline -DHOST_DEBUG
endif

ifeq ($(strip $(DEVICE_DEBUG)), yes)
  NVCCOPT += -G
endif

ifeq ($(strip $(VERBOSE)), yes)
  NVCCOPT += --ptxas-options=-v
endif

ifeq ($(strip $(BLAS_TEX)), no)
  NVCCOPT += -DDIRECT_ACCESS_BLAS
  COPT += -DDIRECT_ACCESS_BLAS
endif

ifeq ($(strip $(FERMI_DBLE_TEX)), no)
  NVCCOPT += -DFERMI_NO_DBLE_TEX
  COPT += -DFERMI_NO_DBLE_TEX
endif

ifeq ($(strip $(GPU_DIRECT)), yes)
  NVCCOPT += -DGPU_DIRECT
  COPT += -DGPU_DIRECT
endif

ifeq ($(strip $(BUILD_QDP_INTERFACE)), yes)
  NVCCOPT += -DBUILD_QDP_INTERFACE
  COPT += -DBUILD_QDP_INTERFACE
endif

ifeq ($(strip $(BUILD_MILC_INTERFACE)), yes)
  NVCCOPT += -DBUILD_MILC_INTERFACE
  COPT += -DBUILD_MILC_INTERFACE
endif

ifeq ($(strip $(BUILD_CPS_INTERFACE)), yes)
  NVCCOPT += -DBUILD_CPS_INTERFACE
  COPT += -DBUILD_CPS_INTERFACE
endif

ifeq ($(strip $(BUILD_QDPJIT_INTERFACE)), yes)
  NVCCOPT += -DBUILD_QDPJIT_INTERFACE
  COPT += -DBUILD_QDPJIT_INTERFACE
endif

ifeq ($(strip $(BUILD_BQCD_INTERFACE)), yes)
  NVCCOPT += -DBUILD_BQCD_INTERFACE
  COPT += -DBUILD_BQCD_INTERFACE
endif

ifeq ($(strip $(DEVICE_PACK)), yes)
  NVCCOPT += -DDEVICE_PACK
  COPT += -DDEVICE_PACK
endif

ifeq ($(strip $(OS)), osx)
  NUMA_AFFINITY = no
endif

ifeq ($(strip $(NUMA_AFFINITY)), yes)
  NVCCOPT += -DNUMA_AFFINITY
  COPT += -DNUMA_AFFINITY
  NUMA_AFFINITY_OBJS=numa_affinity.o
endif


### Next conditional is necessary.
### QDPXX_CXXFLAGS contains "-O3".
### We must make sure its not given
### twice to nvcc. It would complain.

ifeq ($(strip $(USE_QDPJIT)), yes)
  NVCCOPT += -DUSE_QDPJIT
  COPT += -DUSE_QDPJIT
  LIB += $(QDPXX_LDFLAGS) $(QDPXX_LIBS)
  INC += -I$(QDP_INSTALL_PATH)/include

  CFLAGS = -Wall -std=c99 $(COPT) $(INC)
  CXXFLAGS = -Wall $(COPT) $(INC) $(QDPXX_CXXFLAGS)
  NVCC = $(CUDA_INSTALL_PATH)/bin/nvcc 
  NVCCFLAGS = $(NVCCOPT) -arch=$(GPU_ARCH) $(INC)
  LDFLAGS = -fPIC $(LIB)
else
  CFLAGS = -Wall -O3 -std=c99 $(COPT) $(INC)
  CXXFLAGS = -Wall -O3 $(COPT) $(INC)
  NVCC = $(CUDA_INSTALL_PATH)/bin/nvcc 
  NVCCFLAGS = -O3 $(NVCCOPT) -arch=$(GPU_ARCH) $(INC)
  LDFLAGS = -fPIC $(LIB)
endif