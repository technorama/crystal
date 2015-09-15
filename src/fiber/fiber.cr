require "./lib_pcl"

@[NoInline]
fun get_stack_top : Void*
  dummy :: Int32
  pointerof(dummy) as Void*
end

class Fiber
  STACK_SIZE = 8 * 1024 * 1024

  @@mutex = Mutex.new
  @@first_fiber = nil
  @@last_fiber = nil
  @@stack_pool = [] of Void*

  protected property :stack_top
  protected property :stack_bottom
  protected property :next_fiber
  protected property :prev_fiber

  def self.thread_init
    if LibPcl.co_thread_init != 0
      raise Errno.new "co_thread_init"
    end
  end

  def self.thread_cleanup
    LibPcl.co_thread_cleanup
  end

# BUG: not sure if storing thread here is correct.  is necessary to store a ref to Thread somewhere
  def initialize(@thread = nil, &@proc)
    @stack = Fiber.allocate_stack
    @stack_top = @stack_bottom = @stack + STACK_SIZE
    @cr = LibPcl.co_create(->(fiber) { (fiber as Fiber).run }, self as Void*, @stack, STACK_SIZE)
    LibPcl.co_set_data(@cr, self as Void*)

    @prev_fiber = nil
    gc_track
  end

  def initialize
# why does reschedule work on the main thread when the main fiber exits?
    @thread = nil
    @cr = LibPcl.co_current
    @proc = ->{}
    @stack = Pointer(Void).null
    @stack_top = get_stack_top
    @stack_bottom = LibGC.stackbottom
    LibPcl.co_set_data(@cr, self as Void*)

    @@first_fiber = @@last_fiber = self
  end

  protected def self.allocate_stack
@@mutex.synchronize do
    @@stack_pool.pop? || LibC.mmap(nil, LibC::SizeT.new(Fiber::STACK_SIZE),
      LibC::PROT_READ | LibC::PROT_WRITE,
      LibC::MAP_PRIVATE | LibC::MAP_ANON,
      -1, LibC::SSizeT.new(0)).tap do |pointer|
        raise Errno.new("Cannot allocate new fiber stack") if pointer == LibC::MAP_FAILED
      end
end
  end

  def self.stack_pool_collect
@@mutex.synchronize do
    return if @@stack_pool.size == 0
    free_count = @@stack_pool.size > 1 ? @@stack_pool.size / 2 : 1
    free_count.times do
      stack = @@stack_pool.pop
      LibC.munmap(stack, LibC::SizeT.new(Fiber::STACK_SIZE))
    end
end
  end

  def finalize
LibC.printf "Fiber.finalize\n"
  end

  def run
    @proc.call
    @@stack_pool << @stack

    # Remove the current fiber from the linked list

    if prev_fiber = @prev_fiber
      prev_fiber.next_fiber = @next_fiber
    else
      @@first_fiber = @next_fiber
    end

    if next_fiber = @next_fiber
      next_fiber.prev_fiber = @prev_fiber
    else
      @@last_fiber = @prev_fiber
    end

    Scheduler.reschedule unless @thread
  end

  @[NoInline]
  def resume
    Fiber.current.stack_top = get_stack_top

    LibGC.stackbottom = @stack_bottom
    LibPcl.co_call(@cr)
  end

  @[NoInline]
  def mark
    Fiber.current.stack_top = get_stack_top

    LibGC.stackbottom = @stack_bottom
  end

  @[NoInline]
  def thread_run
    LibPcl.co_call(@cr)
  end

  @[NoInline]
  def thread_run
    LibPcl.co_call(@cr)
  end

  def self.current
    if current_data = LibPcl.co_get_data(LibPcl.co_current)
      current_data as Fiber
    else
      raise "Could not get the current fiber"
    end
  end

# needs atomics
  private def gc_track
@@mutex.synchronize do
    if last_fiber = @@last_fiber
      @prev_fiber = last_fiber
      last_fiber.next_fiber = @@last_fiber = self
    else
      @@first_fiber = @@last_fiber = self
    end
end
  end

  protected def push_gc_roots
    # Push the used section of the stack
    LibGC.push_all_eager @stack_top, @stack_bottom

    # PCL stores context (setjmp or ucontext) in the first bytes of the given stack
    ptr = @cr as Void*
    # HACK: the size of the context varies on each platform
    LibGC.push_all_eager ptr, ptr + 1024
  end

  @@prev_push_other_roots = LibGC.get_push_other_roots

  # This will push all fibers stacks whenever the GC wants to collect some memory
  LibGC.set_push_other_roots -> do
@@mutex.synchronize do
    @@prev_push_other_roots.call

    fiber = @@first_fiber
    while fiber
      fiber.push_gc_roots
      fiber = fiber.next_fiber
    end
end
  end

  LibPcl.co_thread_init
  @@root = new

  def self.root
    @@root
  end
end
