require "./lib_pcl"

@[NoInline]
fun get_stack_top : Void*
  dummy :: Int32
  pointerof(dummy) as Void*
end

class Fiber
  STACK_SIZE = 8 * 1024 * 1024

  @@stack_mutex = Mutex.new
  @@gc_mutex = Mutex.new
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

# BUG: remove thread param later
  def initialize(@thread = nil, &@proc)
    @stack = Fiber.allocate_stack
    @stack_top = @stack_bottom = @stack + STACK_SIZE
    @cr = LibPcl.co_create(->(fiber) { (fiber as Fiber).run }, self as Void*, @stack, STACK_SIZE)
    LibPcl.co_set_data(@cr, self as Void*)

    @stack_bottom = LibGC.stackbottom if @thread

    @prev_fiber = nil
    gc_track
  end

  def initialize @thread = nil : Thread?
    @cr = LibPcl.co_current
#LibC.printf "Fiber.new #{@cr} sttop=#{get_stack_top} stbot=#{LibGC.stackbottom}\n"
#LibC.printf "Fiber.new #{get_stack_top - LibGC.stackbottom}\n"
    @proc = ->{}
    @stack = Pointer(Void).null
    @stack_top = get_stack_top
    @stack_bottom = LibGC.stackbottom
# BUG: problems in GC if these are set
if @thread
    @stack_top = Pointer(Void).null
    @stack_bottom = Pointer(Void).null
end

    LibPcl.co_set_data(@cr, self as Void*)

    @prev_fiber = nil
    gc_track
  end

  protected def self.allocate_stack
@@stack_mutex.synchronize do
    @@stack_pool.pop? || LibC.mmap(nil, LibC::SizeT.new(Fiber::STACK_SIZE),
      LibC::PROT_READ | LibC::PROT_WRITE,
      LibC::MAP_PRIVATE | LibC::MAP_ANON,
      -1, LibC::SSizeT.new(0)).tap do |pointer|
        raise Errno.new("Cannot allocate new fiber stack") if pointer == LibC::MAP_FAILED
      end
end
  end

  def self.stack_pool_collect
@@stack_mutex.synchronize do
    return if @@stack_pool.size == 0
    free_count = @@stack_pool.size > 1 ? @@stack_pool.size / 2 : 1
    free_count.times do
      stack = @@stack_pool.pop
      LibC.munmap(stack, LibC::SizeT.new(Fiber::STACK_SIZE))
    end
end
  end

  def finalize2
LibC.printf "Fiber.finalize\n" if ENV.has_key?("DEBUG")
  end

  protected def run
#LibC.printf "Fiber.run has_thread=#{!@thread.nil?} call run\n"
    @proc.call
#LibC.printf "Fiber.run call end\n"
    finished
  end

  # :nodoc:
  def finished
#LibC.printf "Fiber.run #{@cr} finished\n"

@@stack_mutex.synchronize do
    @@stack_pool << @stack
end

@@gc_mutex.synchronize do
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
end

#LibC.printf "Fiber.run reschedule or exiting\n"
    Scheduler.reschedule unless @thread
  end

  @[NoInline]
  def resume
begin
    Fiber.current.stack_top = get_stack_top

#    LibGC.stackbottom = @stack_bottom
rescue ex
	LibC.printf "#{ex}\n"
end
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

  def self.current
    if current_data = LibPcl.co_get_data(LibPcl.co_current)
      current_data as Fiber
    else
      raise "Could not get the current fiber"
    end
  end

# needs atomics
  private def gc_track
@@gc_mutex.synchronize do
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
@@gc_mutex.synchronize do
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
