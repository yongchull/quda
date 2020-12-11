#pragma once

// Target specific definitions in include/targets/XXX/quda_api_target.h
// The correct targets/ directory is set by the build system
// Eventually we want to shrink the contents of that
#include <quda_define.h>

enum qudaMemcpyKind { qudaMemcpyHostToHost, 
	              qudaMemcpyHostToDevice,
		      qudaMemcpyDeviceToHost,
		      qudaMemcpyDeviceToDevice,
		      qudaMemcpyDefault };

#if defined(QUDA_TARGET_CUDA)
#include "targets/cuda/quda_api_target.h"
#elif defined(QUDA_TARGET_HIP)
#include "targets/hip/quda_api_target.h"
#endif


#include <enum_quda.h>

/**
   @file quda_api.h

   Wrappers around CUDA API function calls allowing us to easily
   profile and switch between using the CUDA runtime and driver APIs.
 */

namespace quda
{

  class TuneParam;

  struct qudaStream_t {
    int idx;
    //qudaStream_t(int idx) : idx(idx) {}
  };

  /**
     @brief Wrapper around cudaLaunchKernel
     @param[in] func Device function symbol
     @param[in] tp TuneParam containing the launch parameters
     @param[in] args Arguments
     @param[in] stream Stream identifier
  */
  qudaError_t qudaLaunchKernel(const void *func, const TuneParam &tp, void **args, qudaStream_t stream);

  /**
     @brief Templated wrapper around qudaLaunchKernel which can accept
     a templated kernel, and expects a kernel with a single Arg argument
     @param[in] func Device function symbol
     @param[in] tp TuneParam containing the launch parameters
     @param[in] args Arguments
     @param[in] stream Stream identifier
  */
  template <typename T, typename... Arg>
  qudaError_t qudaLaunchKernel(T *func, const TuneParam &tp, qudaStream_t stream, const Arg &...arg)
  {
    const void *args[] = {&arg...};
    return qudaLaunchKernel(reinterpret_cast<const void *>(func), tp, const_cast<void **>(args), stream);
  }


  /**
     @brief Wrapper around cudaMemcpy or driver API equivalent
     @param[out] dst Destination pointer
     @param[in] src Source pointer
     @param[in] count Size of transfer
     @param[in] kind Type of memory copy
  */
  void qudaMemcpy_(void *dst, const void *src, size_t count, qudaMemcpyKind kind, const char *func, const char *file,
                   const char *line);

  /**
     @brief Wrapper around cudaMemcpyAsync or driver API equivalent
     @param[out] dst Destination pointer
     @param[in] src Source pointer
     @param[in] count Size of transfer
     @param[in] kind Type of memory copy
     @param[in] stream Stream to issue copy
  */
  void qudaMemcpyAsync_(void *dst, const void *src, size_t count, qudaMemcpyKind kind, const qudaStream_t &stream,
                        const char *func, const char *file, const char *line);


  /**
     @brief Wrapper around cudaMemcpyAsync or driver API equivalent for peer-to-peer copies
     @param[out] dst Destination pointer
     @param[in] src Source pointer
     @param[in] count Size of transfer
     @param[in] stream Stream to issue copy
  */
  void qudaMemcpyP2PAsync_(void *dst, const void *src, size_t count, const qudaStream_t &stream,
                           const char *func, const char *file, const char *line);

  /**
     @brief Wrapper around cudaMemcpy2DAsync or driver API equivalent
     @param[out] dst Destination pointer
     @param[in] dpitch Destination pitch in bytes
     @param[in] src Source pointer
     @param[in] spitch Source pitch in bytes
     @param[in] width Width in bytes
     @param[in] height Number of rows
     @param[in] kind Type of memory copy
  */
  void qudaMemcpy2D_(void *dst, size_t dpitch, const void *src, size_t spitch, size_t width, size_t height,
                     qudaMemcpyKind kind, const char *func, const char *file, const char *line);

  /**
     @brief Wrapper around cudaMemcpy2DAsync or driver API equivalent
     @param[out] dst Destination pointer
     @param[in] dpitch Destination pitch in bytes
     @param[in] src Source pointer
     @param[in] spitch Source pitch in bytes
     @param[in] width Width in bytes
     @param[in] height Number of rows
     @param[in] kind Type of memory copy
     @param[in] stream Stream to issue copy
  */
  void qudaMemcpy2DAsync_(void *dst, size_t dpitch, const void *src, size_t spitch, size_t width, size_t height,
                          qudaMemcpyKind kind, const qudaStream_t &stream, const char *func, const char *file,
                          const char *line);

  /**
     @brief Wrapper around cudaMemcpy2DAsync or driver API equivalent
     @param[out] dst Destination pointer
     @param[in] dpitch Destination pitch in bytes
     @param[in] src Source pointer
     @param[in] spitch Source pitch in bytes
     @param[in] width Width in bytes
     @param[in] height Number of rows
     @param[in] stream Stream to issue copy
  */
  void qudaMemcpy2DP2PAsync_(void *dst, size_t dpitch, const void *src, size_t spitch, size_t width, size_t height,
                             const qudaStream_t &stream, const char *func, const char *file, const char *line);

  /**
     @brief Wrapper around cudaMemset or driver API equivalent
     @param[out] ptr Starting address pointer
     @param[in] value Value to set for each byte of specified memory
     @param[in] count Size in bytes to set
   */
  void qudaMemset_(void *ptr, int value, size_t count, const char *func, const char *file, const char *line);

  /**
     @brief Wrapper around cudaMemset2D or driver API equivalent
     @param[out] ptr Starting address pointer
     @param[in] Pitch in bytes
     @param[in] value Value to set for each byte of specified memory
     @param[in] width Width in bytes
     @param[in] height Height in bytes
   */
  void qudaMemset2D_(void *ptr, size_t pitch, int value, size_t width, size_t height, const char *func,
                     const char *file, const char *line);

  /**
     @brief Wrapper around cudaMemsetAsync or driver API equivalent
     @param[out] ptr Starting address pointer
     @param[in] value Value to set for each byte of specified memory
     @param[in] count Size in bytes to set
     @param[in] stream Stream to issue memset
   */
  void qudaMemsetAsync_(void *ptr, int value, size_t count, const qudaStream_t &stream, const char *func,
                        const char *file, const char *line);

  /**
     @brief Wrapper around cudaMemsetAsync or driver API equivalent
     @param[out] ptr Starting address pointer
     @param[in] Pitch in bytes
     @param[in] value Value to set for each byte of specified memory
     @param[in] width Width in bytes
     @param[in] height Height in bytes
     @param[in] stream Stream to issue memset
   */
  void qudaMemset2DAsync_(void *ptr, size_t pitch, int value, size_t width, size_t height, const qudaStream_t &stream,
                          const char *func, const char *file, const char *line);

  /**
     @brief Wrapper around cudaMemPrefetchAsync or driver API equivalent
     @param[out] ptr Starting address pointer to be prefetched
     @param[in] count Size in bytes to prefetch
     @param[in] mem_space Memory space to prefetch to
     @param[in] stream Stream to issue prefetch
   */
  void qudaMemPrefetchAsync_(void *ptr, size_t count, QudaFieldLocation mem_space, const qudaStream_t &stream,
                             const char *func, const char *file, const char *line);

  /**
     @brief Wrapper around cudaEventCreate or cuEventCreate  with built-in error checking
     @param[in] pointer to event we are creating
   */
  void qudaEventCreate_(qudaEvent_t *event, const char *func, const char *file, const char *line);


   /**
     @brief Wrapper around cudaEventCreateWithFlags (or cuEventCreate) with disabled timing with built-in error checking
     @param[in] pointer to event we are creating
   */
  void qudaEventCreateDisableTiming_(qudaEvent_t *event, const char *func, const char *file, const char *line);


  /**
     @brief Wrapper around cudaEventCreateWithFlags (or cuEventCreate) with disabled timing with built-in error checking
     @param[in] pointer to event we are creating
   */
  void qudaEventCreateIpcDisableTiming_(qudaEvent_t *event, const char *func, const char *file, const char *line);
  
   /**
     @brief Wrapper around cudaEventDestroy or cuEventDestroy with built-in error checking
     @param[in] pointer to event we are desroying
   */
  void qudaEventDestroy_(qudaEvent_t event, const char *func, const char *file, const char *line);
  
  /**
     @brief Wrapper around cudaEventQuery or cuEventQuery with built-in error checking
     @param[in] event Event we are querying
     @return true if event has been reached
   */
  bool qudaEventQuery_(qudaEvent_t &event, const char *func, const char *file, const char *line);

  
  /**
     @brief Wrapper around cudaEventRecord or cuEventRecord with
     built-in error checking
     @param[in,out] event Event we are recording
     @param[in,out] stream Stream where to record the event
   */
  void qudaEventRecord_(qudaEvent_t &event, qudaStream_t stream, const char *func, const char *file, const char *line);


  /**
     @brief Wrapper around cudaEventElapsedTime or cuEventElapsedTime
     built-in error checking
     @param[in,out] ms the elapsed time in milliseconds
     @param[in] start the event at the start of the time period
     @param[in] end   the event at the end of the time period
   */
  void qudaEventElapsedTime_(float *ms, qudaEvent_t start, qudaEvent_t end, const char *func, const char *file, const char *line);
  
  /**
     @brief Wrapper around cudaStreamWaitEvent or cuStreamWaitEvent
     with built-in error checking
     @param[in,out] stream Stream which we are instructing to wait
     @param[in] event Event we are waiting on
     @param[in] flags Flags to pass to function
   */
  void qudaStreamWaitEvent_(qudaStream_t stream, qudaEvent_t event, unsigned int flags, const char *func,
                            const char *file, const char *line);

  /**
     @brief Wrapper around cudaEventSynchronize or cuEventSynchronize
     with built-in error checking
     @param[in] event Event which we are synchronizing with respect to
   */
  void qudaEventSynchronize_(qudaEvent_t event, const char *func, const char *file, const char *line);

#if defined(QUDA_ENABLE_P2P)
  /** 
      @brief Wrapper aroud cudaIpcGetEventHandle or cuIpcGetEventHandle with built in error checking
      @param[in,out] the handle
      @param[in] the event
  */
  void qudaIpcGetEventHandle_(qudaIpcEventHandle_t *handle, qudaEvent_t event, const char *func, const char *file,
			      const char *line);


 /**
      @brief Wrapper aroud cudaIpcGetMemHandle with built in error checking
      @param[in,out] the handle
      @param[in] the ptr 
  */
  void qudaIpcGetMemHandle_(qudaIpcMemHandle_t *handle, void *devPtr, const char *func, const char *file,
                              const char *line);


   /**
      @brief Wrapper aroud cudaIpcOpenEventHandle or cuIpcOpenEventHandle  with built in error checking
      @param[in,out] the event
      @param[in] the handle
  */
  void qudaIpcOpenEventHandle_(qudaEvent_t *event, qudaIpcEventHandle_t handle, const char *func, const char *file,
                              const char *line);

  /**
     @brief Wrapper aroud cudaIpcOpenMemHandle with built in error checking for lazyPeer2Peer access
     @param[in,out] the device pointer
     @param[in] the handle
  */
  void qudaIpcOpenMemHandle_(void **devPtr, qudaIpcMemHandle_t handle, const char *func, const char *file,
                              const char *line);
  /**
     @brief Wrapper aroud cudaIpcCloseMemHandle with built in error checking for lazyPeer2Peer access
     @param[in,out] the device pointer
  */
  void qudaIpcCloseMemHandle_(void *devPtr, const char *func, const char *file, const char *line);
#endif

  
  /**
     @brief Wrapper around cudaStreamSynchronize or
     cuStreamSynchronize with built-in error checking
     @param[in] stream Stream which we are synchronizing
  */
  void qudaStreamSynchronize_(const qudaStream_t &stream, const char *func, const char *file, const char *line);

  /**
     @brief Wrapper around cudaDeviceSynchronize or
     cuDeviceSynchronize with built-in error checking
   */
  void qudaDeviceSynchronize_(const char *func, const char *file, const char *line);

  /**
     @brief Wrapper around cudaGetSymbolAddress with built in error
     checking.  Returns the address of symbol on the device; symbol
     is a variable that resides in global memory space.

     @param[in] symbol Global variable or string symbol to search for
     @return Return device pointer associated with symbol
  */
  void* qudaGetSymbolAddress_(const char *symbol, const char *func, const char *file, const char *line);


  /**
     @brief Print out the timer profile for CUDA API calls
   */
  void printAPIProfile();

} // namespace quda

#define STRINGIFY__(x) #x
#define __STRINGIFY__(x) STRINGIFY__(x)

#define qudaMemcpy(dst, src, count, kind)                                                                              \
  ::quda::qudaMemcpy_(dst, src, count, kind, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaMemcpyAsync(dst, src, count, kind, stream)                                                \
  ::quda::qudaMemcpyAsync_(dst, src, count, kind, stream, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaMemcpyP2PAsync(dst, src, count, stream)                     \
  ::quda::qudaMemcpyP2PAsync_(dst, src, count, stream, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaMemcpy2D(dst, dpitch, src, spitch, width, height, kind)                                                    \
  ::quda::qudaMemcpy2D_(dst, dpitch, src, spitch, width, height, kind, __func__, quda::file_name(__FILE__),            \
                        __STRINGIFY__(__LINE__))

#define qudaMemcpy2DAsync(dst, dpitch, src, spitch, width, height, kind, stream)                                       \
  ::quda::qudaMemcpy2DAsync_(dst, dpitch, src, spitch, width, height, kind, stream, __func__,                          \
                             quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaMemcpy2DP2PAsync(dst, dpitch, src, spitch, width, height, stream)                                       \
  ::quda::qudaMemcpy2DP2PAsync_(dst, dpitch, src, spitch, width, height, stream, __func__,                          \
                                quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaMemset(ptr, value, count)                                                                                  \
  ::quda::qudaMemset_(ptr, value, count, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaMemset2D(ptr, pitch, value, width, height)                                                                 \
  ::quda::qudaMemset2D_(ptr, pitch, value, width, height, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaMemsetAsync(ptr, value, count, stream)                                                                     \
  ::quda::qudaMemsetAsync_(ptr, value, count, stream, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaMemset2DAsync(ptr, pitch, value, width, height, stream)                                                    \
  ::quda::qudaMemset2DAsync_(ptr, pitch, value, width, height, stream, __func__, quda::file_name(__FILE__),            \
                             __STRINGIFY__(__LINE__))

#define qudaMemPrefetchAsync(ptr, count, mem_space, stream)                                                            \
  ::quda::qudaMemPrefetchAsync_(ptr, count, mem_space, stream, __func__, quda::file_name(__FILE__),                    \
                                __STRINGIFY__(__LINE__))

// IN HERE BECAUSE OF BLOCK ORTHOGONALIZE
#define qudaMemcpyToSymbolAsync(symbol, src, count,offset,kind,stream)                                           \
  ::quda::qudaMemcpyToSymbolAsync_(symbol,src, count, offset, kind, stream, __func__, quda::file_name(__FILE__), \
		  __STRINGIFY__(__LINE__))

#define qudaEventCreate(event)                                                                                         \
  ::quda::qudaEventCreate_(event, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaEventCreateDisableTiming(event)				\
  ::quda::qudaEventCreateDisableTiming_(event, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaEventCreateIpcDisableTiming(event)                           \
  ::quda::qudaEventCreateIpcDisableTiming_(event, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))  

#define qudaEventDestroy(event)				\
  ::quda::qudaEventDestroy_(event, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaEventQuery(event)                                                                                          \
  ::quda::qudaEventQuery_(event, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaEventRecord(event, stream)                                                                                 \
  ::quda::qudaEventRecord_(event, stream, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaEventElapsedTime(ms, start,end)                                                                            \
  ::quda::qudaEventElapsedTime_(ms,start,end, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaIpcGetEventHandle(handle,event)                                                                            \
  ::quda::qudaIpcGetEventHandle_(handle,event, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaIpcGetMemHandle(handle,ptr)                                                                            \
  ::quda::qudaIpcGetMemHandle_(handle,ptr, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define	qudaIpcOpenEventHandle(handle,event)   	      	      	      	      	      	      	      	      	       \
  ::quda::qudaIpcOpenEventHandle_(handle,event, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define	qudaIpcOpenMemHandle(ptr,handle)				\
  ::quda::qudaIpcOpenMemHandle_(ptr,handle, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaIpcCloseMemHandle(ptr)											\
  ::quda::qudaIpcCloseMemHandle_(ptr, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))
  
#define qudaStreamWaitEvent(stream, event, flags)                                                                      \
  ::quda::qudaStreamWaitEvent_(stream, event, flags, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaEventSynchronize(event)                                                                                    \
  ::quda::qudaEventSynchronize_(event, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaStreamSynchronize(stream)                                                                                  \
  ::quda::qudaStreamSynchronize_(stream, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaDeviceSynchronize()                                                                                        \
  ::quda::qudaDeviceSynchronize_(__func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

#define qudaGetSymbolAddress(symbol)                                    \
  ::quda::qudaGetSymbolAddress_(symbol, __func__, quda::file_name(__FILE__), __STRINGIFY__(__LINE__))

