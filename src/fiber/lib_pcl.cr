@[Link("pcl")]
lib LibPcl
  alias Int = LibC::Int

  type Coroutine = Void*

  fun co_thread_init : Int
  fun co_thread_cleanup
  fun co_create(func : (Void* ->), data : Void*, stack : Void*, size : Int) : Coroutine
  fun co_call(cr : Coroutine)
  fun co_resume
  fun co_current : Coroutine
  fun co_get_data(cr : Coroutine) : Void*
  fun co_set_data(cr : Coroutine, data : Void*) : Void*
end
