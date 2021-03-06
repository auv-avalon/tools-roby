module Roby::TaskStructure
    relation :PlannedBy, :child_name => :planning_task, 
	:parent_name => :planned_task, :noinfo => true, :single_child => true do

        # Returns the first child enumerated by planned_tasks. This is a
        # convenience method that can be used if it is known that the planning
        # task is only planning for one single task (a pretty common case)
        def planned_task; planned_tasks.find { true } end
	# The set of tasks which are planned by this one
	def planned_tasks; parent_objects(PlannedBy) end
	# Set +task+ as the planning task of +self+
        def planned_by(task, options = {})
            if task.respond_to?(:as_plan)
                task = task.as_plan
            end

            options = Kernel.validate_options options,
                :replace => false, :optional => false, :plan_early => true

            allow_replace = options.delete(:replace)
	    if old = planning_task
		if allow_replace
		    remove_planning_task(old)
		else
		    raise ArgumentError, "this task already has a planner"
		end
	    end
	    add_planning_task(task, options)
            if !options[:plan_early]
                task.schedule_as(self)
            end

            task
        end
    end

    # Returns a set of PlanningFailedError exceptions for all abstract tasks
    # for which planning has failed
    def PlannedBy.check_structure(plan)
	result = []
	PlannedBy.each_edge do |planned_task, planning_task, options|
	    next if plan != planning_task.plan
            next if !planning_task.failed?
            next if !planned_task.self_owned?

	    if (planned_task.pending? && !planned_task.executable?) || !options[:optional]
                result << [Roby::PlanningFailedError.new(planned_task, planning_task), []]
            end
	end

	result
    end
end

module Roby
    # This exception is raised when a task is abstract, and its planner failed:
    # the system will therefore not have a suitable executable development for
    # this task, and this is a failure
    class PlanningFailedError < LocalizedError
	# The planning task
        attr_reader :planning_task
        # The planned task
        def planned_task; failed_task end

	def initialize(planned_task, planning_task)
            @planning_task = planning_task
	    super(planned_task)
	end
        def pretty_print(pp)
            pp.text "failed to plan "
            planned_task.pretty_print(pp)
            pp.breakable

            planning_task.pretty_print(pp)
            pp.breakable
            pp.text " failed with "
            pp_failure_reason(pp, planning_task.failure_reason)
        end
    end
end

