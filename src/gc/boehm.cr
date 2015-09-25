@[Link("pthread")]
@[Link("gc")]
lib LibGC
  alias Int = LibC::Int
  alias SizeT = LibC::SizeT
  alias Word = LibC::ULong

  fun init = GC_init
  fun malloc = GC_malloc(size : SizeT) : Void*
  fun malloc_atomic = GC_malloc_atomic(size : SizeT) : Void*
  fun realloc = GC_realloc(ptr : Void*, size : SizeT) : Void*
  fun free = GC_free(ptr : Void*)
  fun collect_a_little = GC_collect_a_little : Int
  fun collect = GC_gcollect
  fun add_roots = GC_add_roots(low : Void*, high : Void*)
  fun enable = GC_enable
  fun disable = GC_disable
  fun set_handle_fork = GC_set_handle_fork(value : Int)

  type Finalizer = Void*, Void* ->
  fun register_finalizer = GC_register_finalizer(obj : Void*, fn : Finalizer, cd : Void*, ofn : Finalizer*, ocd : Void**)
  fun register_finalizer_ignore_self = GC_register_finalizer_ignore_self(obj : Void*, fn : Finalizer, cd : Void*, ofn : Finalizer*, ocd : Void**)
  fun invoke_finalizers = GC_invoke_finalizers : Int

  fun get_heap_usage_safe = GC_get_heap_usage_safe(heap_size : Word*, free_bytes : Word*, unmapped_bytes : Word*, bytes_since_gc : Word*, total_bytes : Word*)
  fun set_max_heap_size = GC_set_max_heap_size(Word)

  fun get_start_callback = GC_get_start_callback : Void*
  fun set_start_callback = GC_set_start_callback(callback : ->)

  fun set_push_other_roots = GC_set_push_other_roots(proc : ->)
  fun get_push_other_roots = GC_get_push_other_roots : ->

  fun push_all_eager = GC_push_all_eager(bottom : Void*, top : Void*)
  fun push_all_stack = GC_push_all_stack(bottom : Void*, top : Void*)

  # Incomplete on IA64.  This should really be imported from a C header.
  struct StackBase
    base : Void*
  end

  fun get_stack_base = GC_get_stack_base(StackBase*)
  fun register_altstack = GC_register_altstack(stack : Void*, ssize : SizeT, astack : Void*, asize : SizeT)

  $stackbottom = GC_stackbottom : Void*
end

# Boehm GC requires to use GC_pthread_create and GC_pthread_join instead of pthread_create and pthread_join
lib LibPThread
  fun create = GC_pthread_create(thread : Thread*, attr : Void*, start : Void* ->, arg : Void*) : LibC::Int
  fun join = GC_pthread_join(thread : Thread, value : Void**) : LibC::Int
  fun detach = GC_pthread_detach(thread : Thread) : LibC::Int
end

# :nodoc:
fun __crystal_malloc(size : UInt32) : Void*
  LibGC.malloc(size)
end

# :nodoc:
fun __crystal_malloc_atomic(size : UInt32) : Void*
  LibGC.malloc_atomic(size)
end

# :nodoc:
fun __crystal_realloc(ptr : Void*, size : UInt32) : Void*
  LibGC.realloc(ptr, size)
end

module GC
  def self.init
    LibGC.set_handle_fork(1)
    LibGC.init
  end

  def self.collect
    LibGC.collect
  end

  def self.enable
    LibGC.enable
  end

  def self.disable
    LibGC.disable
  end

  def self.free(pointer : Void*)
    LibGC.free(pointer)
  end

  def self.add_finalizer(object : T)
    if object.responds_to?(:finalize)
      LibGC.register_finalizer_ignore_self(object as Void*,
        ->(obj, data) {
          same_object = obj as T
          if same_object.responds_to?(:finalize)
            same_object.finalize
          end
        }, nil, nil, nil)
      nil
    end
  end

  def self.add_root(object : Reference)
    roots = $roots ||= [] of Pointer(Void)
    roots << Pointer(Void).new(object.object_id)
  end

  def self.stack_base
    LibGC.get_stack_base out sb
    sb
  end
end
