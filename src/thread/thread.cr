require "./*"

# :nodoc:
class Thread(T, R)
  # Don't use this class, it is used internally by the event scheduler.
  # Use spawn and channels instead.

  def self.new(&func : -> R)
    Thread(Nil, R).new(nil) { func.call }
  end

  def self.new_worker(&func : -> R)
    Thread(Nil, R).new(nil, use_fiber: false) { func.call }
  end

# race condition
  def self.mutex
    @@mutex ||= Mutex.new
  end

  def self.threads
    @@threads ||= begin
      mutex.synchronize do
        @@threads ||= Array(Thread(Nil, Nil)).new
      end
    end
  end

 def initialize(arg : T, @use_fiber = true, &func : T -> R)
    @func = func
    @arg = arg
    @detached = false
    ret = LibPThread.create(out @th, nil, ->(data) {
        (data as Thread(T, R)).start
      }, self as Void*)
    if ret != 0
      raise Errno.new("pthread_create")
    end

#    threads = self.class.threads
#self.class.mutex.synchronize do
#    threads << self
#end
  end

  def finalize
#LibC.printf "#{self}.finalize\n" if ENV.has_key?("DEBUG")
    LibPThread.detach(@th) unless @detached
  end

  def join
    if LibPThread.join(@th, out _ret) != 0
      raise Errno.new("pthread_join")
    end
    @detached = true

    if exception = @exception
      raise exception
    end

    # TODO: We need to cast ret to R, otherwise it'll be nilable
    # and we don't want that. But `@ret as R` gives
    # `can't cast Nil to NoReturn` in the case when the Thread's body is
    # NoReturn. The following trick works, but we should find another
    # way to do it.
    ret = @ret
    if ret.is_a?(R) # Always true
      ret
    else
      exit 242 # unreachable, really
    end
  end

  protected def start
LibC.printf "#{self}.start begin\n" if ENV.has_key?("DEBUG")
    Fiber.thread_init

    begin
      @fiber = Fiber.new self
      @ret = @func.call(@arg)
    rescue ex
      @exception = ex
    ensure
#LibC.printf "#{self}.start ensure (exiting)\n" if ENV.has_key?("DEBUG")
      @fiber.try &.finished
#LibC.printf "#{self}.start ensure after fiber.finished\n" if ENV.has_key?("DEBUG")
      @fiber = nil
      Fiber.thread_cleanup
    end
  end
end


