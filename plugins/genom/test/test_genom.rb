require 'roby/test/common'
require 'roby/app'
require 'genom/runner'

Roby.app.plugin_dir File.expand_path('../..', File.dirname(__FILE__))
Roby.app.using 'genom'

BASE_TEST_DIR = File.expand_path(File.dirname(__FILE__))
path=ENV['PATH'].split(':')
pkg_config_path=(ENV['PKG_CONFIG_PATH'] || "").split(':')

Dir.glob("#{BASE_TEST_DIR}/prefix.*") do |p|
    path << "#{p}/bin"
    pkg_config_path << "#{p}/lib/pkgconfig"
end
ENV['PATH'] = path.join(':')
ENV['PKG_CONFIG_PATH'] = pkg_config_path.join(':')

class TC_Genom < Test::Unit::TestCase
    include Roby::Test
    Runner = ::Genom::Runner

    def env; Runner.environment end
    def setup
	super

        Runner.environment || Runner.h2 
    end
    def teardown
	Roby.control.disable_propagation do
	    Genom.connect do
		env.stop_module('mockup')
		env.stop_module('init_test')
	    end
	end
	super
    end

    def test_def
        model = Genom::GenomModule('mockup')
        assert_nothing_raised { Roby::Genom::Mockup }
        assert_nothing_raised { Roby::Genom::Mockup::Start }
        assert_nothing_raised { Roby::Genom::Mockup::SetIndex }
	assert_equal("Roby::Genom::Mockup::Start", Roby::Genom::Mockup::Start.name)

	task = Roby::Genom::Mockup.start!
	# assert_equal("#<Roby::Genom::Mockup::Start!0x#{task.address.to_s(16)}>", task.model.to_s)
    end

    def test_argument_checking
	model = Genom::GenomModule('mockup')
	assert_raises(ArgumentError) { model::SetIndex.new(:new_value => 10, :bla => 20) }
	assert_raises(TypeError) { model::SetIndex.new(:new_value => "bla") }
    end

    def test_runner_task
        Genom.connect do
            Genom::GenomModule('mockup')
            plan.discover(runner = Genom::Mockup.runner!)
	    
	    runner.start!
	    assert_happens do
		assert(runner.running?)
	    end

	    assert(runner.running?)
	    assert(runner.event(:ready).happened?)

	    runner.stop!
	    assert_event( runner.event(:stop) )

	    plan.discover(runner = Genom::Mockup.runner!)
	    runner.start!
	    assert_event( runner.event(:start) )
	    Process.kill 'INT', Genom::Mockup.genom_module.pid
	    assert_event( runner.event(:failed) )
        end
    end

    def test_init
	mod = Genom::GenomModule('init_test')

	# There is no init singleton method, should fail
	assert_raises(ArgumentError) do
	    Genom.connect { mod.runner! }
	end
	
	# Create the ::init singleton method
	init_period = nil
	mod.singleton_class.class_eval do
	    include Test::Unit::Assertions
	    define_method(:init) do
		assert(mod.genom_module.roby_runner_task.running?)
	       	init_period = init!(42)
	    end
	end

	did_start = false
	mod::Init.on(:start) { did_start = true }
	Genom.connect do
	    plan.discover(runner = mod.runner!)
	    runner.start!

	    assert_happens do
		assert(runner.running?)
	    end

	    assert( init_period )
	    assert( Genom.running.include?(init_period) )
	    assert( init_period.event(:start).pending? )

	    assert_event( init_period.event(:success) )
	    assert_event( runner.event(:ready) )

	    mod.genom_module.poster(:index).wait
	    assert_equal(42, mod.genom_module.index!.update_period)
	end
	assert(did_start)
    end
            
    def test_event_handling
        ::Genom.connect do
            Genom::GenomModule('mockup')

            plan.discover(runner = Genom::Mockup.runner!)
	    runner.start!
	    assert_event( runner.event(:ready) )

	    plan.permanent(task = Genom::Mockup.start!)
	    assert_equal(Genom::Mockup::Runner, task.class.execution_agent)
	    
	    task.start!
	    assert_event( task.event(:start) )
	    
	    task.stop!
	    assert(!task.finished?)
	    assert_event( task.event(:stop) )
	    assert(task.finished?)
        end
    end

    def test_control_to_exec
	mod = Genom::GenomModule('mockup')

	control_task = mod.set_index!(5)
	exec_task    = mod.control_to_exec(:set_index!, 5)
	assert_equal(Genom::Mockup::Runner, control_task.class.execution_agent)
	assert_equal(Genom::Mockup::Runner, exec_task.class.execution_agent)
    end

    def test_needs_precondition
	mod = Genom::GenomModule('mockup')
	Roby::Genom::Mockup::Start.class_eval do
	    needs :SetIndex
	end

	GC.start

	::Genom.connect do
	    plan.discover(runner = Genom::Mockup.runner!)
	    runner.start!
	    assert_event( runner.event(:ready) )

	    plan.permanent(task = Genom::Mockup.start!)
	    assert_raises(Roby::EventPreconditionFailed) { task.start!(nil) }
	end
    end
end
