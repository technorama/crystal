require "./*"

# :nodoc:
class Thread(T, R)
  # Don't use this class, it is used internally by the event scheduler.
  # Use spawn and channels instead.

  def self.new(&func : -> R)
    Thread(Nil, R).new(nil) { func.call }
  end

  def initialize(arg : T, &func : T -> R)
    @func = func
    @arg = arg
    @detached = false
    ret = LibPThread.create(out @th, nil, ->(data) {
        (data as Thread(T, R)).start
      }, self as Void*)

    if ret != 0
      raise Errno.new("pthread_create")
    end
  end

  def finalize
LibC.printf "#{self}.finalize\n"
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
    begin
      Fiber.thread_init
      fiber = Fiber.new(thread: self) do
        @ret = @func.call(@arg)
      end
LibC.printf "Thread.start fiber.resume\n"
      fiber.thread_run
#      @ret = @func.call(@arg)
LibC.printf "Thread.start fiber.end\n"
    rescue ex
LibC.printf "Thread.start #{ex} #{ex.backtrace}\n"
      @exception = ex
    ensure
      Fiber.thread_cleanup
    end
  end
end
