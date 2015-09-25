enum E
	One	= 1
	Two	= 2
	Three	= 3
end

def foo(a	= 1,
	b	= 2
	cccccccccccccccccc	= 3
	)

	foo	=	bar
	zzzzzzzzzzzzzz	=	2
	zzzzzzzzz	=	2
end


class Foo; end

def recur_test a = Array(Foo).new
	a << Foo.new
	return if a.size > 5000
#	recur_test(a) if rand(3) == 0
	recur_test(a.dup)
end

threads = 4.times.map do
	Thread.new do
		loop do
			recur_test
			Foo.new
		end

		nil
	end
end.to_a

10.times do
	spawn do
		loop do
			recur_test
			Scheduler.yield
		end
	end
end

loop { recur_test; Scheduler.yield }

puts "end"
sleep 1

threads.each &.join
threads.clear
