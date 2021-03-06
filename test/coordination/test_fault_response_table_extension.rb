require 'syskit/test'

describe Syskit::Coordination::Models::FaultResponseTableExtension do
    include Syskit::SelfTest

    it "should attach the associated data monitoring tables to the plan it is attached to" do
        component_m = Syskit::TaskContext.new_submodel
        fault_m = Roby::Coordination::FaultResponseTable.new_submodel
        data_m = Syskit::Coordination::DataMonitoringTable.new_submodel(:root => component_m)
        fault_m.use_data_monitoring_table data_m
        flexmock(plan).should_receive(:use_data_monitoring_table).with(data_m, Hash.new).once
        plan.use_fault_response_table fault_m
    end

    it "should remove the associated data monitoring tables from the plan when it is removed from it" do
        component_m = Syskit::TaskContext.new_submodel
        fault_m = Roby::Coordination::FaultResponseTable.new_submodel
        data_m = Syskit::Coordination::DataMonitoringTable.new_submodel(:root => component_m)
        fault_m.use_data_monitoring_table data_m

        assert plan.data_monitoring_tables.empty?
        fault = plan.use_fault_response_table fault_m
        active_tables = plan.data_monitoring_tables
        assert_equal 1, active_tables.size
        table = active_tables.first
        flexmock(plan).should_receive(:remove_data_monitoring_table).with(table).once.pass_thru
        plan.remove_fault_response_table fault
        assert plan.data_monitoring_tables.empty?
    end

    it "should allow using monitors as fault descriptions, and properly set them up at runtime" do
        recorder = flexmock
        response_task_m = Roby::Task.new_submodel do
            terminates
        end
        component_m = Syskit::TaskContext.new_submodel(:name => 'Test') do
            output_port 'out1', '/int'
            output_port 'out2', '/int'
        end
        table_model = Roby::Coordination::FaultResponseTable.new_submodel do
            data_monitoring_table do
                root component_m
                monitor("threshold", out1_port).
                    trigger_on do |sample|
                        recorder.called(sample)
                        sample > 10
                    end.
                    raise_exception
            end
            on_fault threshold_monitor do
                locate_on_origin
                response = task(response_task_m)
                execute response
            end
        end

        plan.use_fault_response_table table_model
        assert_equal Array[table_model.data_monitoring_tables.first.table],
            plan.data_monitoring_tables.map(&:model)
        stub_syskit_deployment_model(component_m)
        component = deploy(component_m)
        syskit_start_component(component)
        process_events
        process_events

        recorder.should_receive(:called).with(5).once.ordered
        recorder.should_receive(:called).with(11).once.ordered
        component.orocos_task.out1.write(5)
        process_events
        component.orocos_task.out1.write(11)
        process_events

        assert(response_task = plan.find_tasks(response_task_m).running.first)
    end

    describe "argument passing" do
        attr_reader :component_m, :data_m, :fault_m

        before do
            @data_m = Syskit::Coordination::DataMonitoringTable.new_submodel
            data_m.argument :arg
            @fault_m = Roby::Coordination::FaultResponseTable.new_submodel
            fault_m.argument :test_arg
        end


        it "should allow giving static arguments to the used data monitoring tables" do
            fault_m.use_data_monitoring_table data_m, :arg => 10
            flexmock(plan).should_receive(:use_data_monitoring_table).once.with(data_m, :arg => 10)
            plan.use_fault_response_table fault_m, :test_arg => 20
        end

        it "should allow passing fault response arguments to the used data monitoring tables" do
            fault_m.use_data_monitoring_table data_m, :arg => fault_m.test_arg
            flexmock(plan).should_receive(:use_data_monitoring_table).once.with(data_m, :arg => 10)
            plan.use_fault_response_table fault_m, :test_arg => 10
        end

        it "should allow passing fault response arguments that are also name of arguments on the fault response table" do
            fault_m.use_data_monitoring_table data_m, :arg => :test_arg
            flexmock(plan).should_receive(:use_data_monitoring_table).once.with(data_m, :arg => :test_arg)
            plan.use_fault_response_table fault_m, :test_arg => 10
        end

        it "should raise if the embedded data monitoring table requires arguments that do not exist on the fault response table" do
            assert_raises(ArgumentError) do
                Roby::Coordination::FaultResponseTable.new_submodel do
                    data_monitoring_table { argument :bla }
                end
            end
        end

        it "should allow the embedded data monitoring table to have optional arguments" do
            fault_m = Roby::Coordination::FaultResponseTable.new_submodel do
                data_monitoring_table do
                    argument :arg, :default => 10
                end
            end
            flexmock(plan).should_receive(:use_data_monitoring_table).once.with(fault_m.data_monitoring_table, Hash.new)
            plan.use_fault_response_table fault_m
        end
        it "should allow used data monitoring tables to have optional arguments" do
            data_m = Syskit::Coordination::DataMonitoringTable.new_submodel
            data_m.argument :arg, :default => 10
            fault_m = Roby::Coordination::FaultResponseTable.new_submodel
            fault_m.use_data_monitoring_table data_m
            flexmock(plan).should_receive(:use_data_monitoring_table).once.with(data_m, Hash.new)
            plan.use_fault_response_table fault_m
        end
    end
end
