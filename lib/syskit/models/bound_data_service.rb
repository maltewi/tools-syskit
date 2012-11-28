module Syskit
    module Models
        # Representation of a data service as provided by a component model
        class BoundDataService
            # The task model which provides this service
            attr_reader :component_model
            # The service name
            attr_reader :name
            # The master service (if there is one)
            attr_reader :master
            # The service model
            attr_reader :model
            # The mappings needed between the ports in the service interface and
            # the actual ports on the component
            attr_reader :port_mappings

            # The service's full name, i.e. the name with which it is referred
            # to in the task model
            attr_reader :full_name

            # True if this service is not a slave service
            def master?; !@master end

            def ==(other)
                other.kind_of?(self.class) &&
                    other.full_name == full_name &&
                    other.component_model == component_model
            end

            def initialize(name, component_model, master, model, port_mappings)
                @name, @component_model, @master, @model, @port_mappings = 
                    name, component_model, master, model, port_mappings

                @full_name =
                    if master
                        "#{master.name}.#{name}"
                    else
                        name
                    end

                @declared_dynamic_slaves = Array.new
            end

            def overload(new_component_model)
                result = dup
                result.instance_variable_set :@component_model, new_component_model
                result
            end

            def to_s
                "#<Models::BoundDataService: #{component_model.short_name} #{full_name}>"
            end

            def short_name
                "#{component_model.short_name}:#{full_name}"
            end

            # Returns a view of this service as a provider of +service_model+
            #
            # It allows to transparently apply port mappings as if +self+ was a
            # service of type +service_model+
            def as(service_model)
                result = dup
                result.instance_variable_set(:@model, service_model)

                mappings = port_mappings.dup
                mappings.delete_if do |srv, _|
                    !service_model.fullfills?(srv)
                end
                result.instance_variable_set(:@port_mappings, mappings)
                result
            end

            def fullfills?(models)
                if !models.respond_to?(:each)
                    models = [models]
                end
                components, services = models.partition { |m| m <= Syskit::Component }
                (components.empty? || self.component_model.fullfills?(components)) &&
                    (services.empty? || self.model.fullfills?(services))
            end

            # Returns the port mappings that should be applied from the service
            # model +model+ to the providing task
            #
            # The returned value is a hash of the form
            #
            #   service_port_name => task_port_name
            #
            def port_mappings_for_task
                port_mappings_for(model)
            end

            # Returns the port mappings that should be applied from the service
            # model +service_model+ to the providing task
            #
            # The returned value is a hash of the form
            #
            #   service_port_name => task_port_name
            #
            def port_mappings_for(service_model)
                if !(result = port_mappings[service_model])
                    raise ArgumentError, "#{service_model} is not provided by #{model.short_name}"
                end
                result
            end

            def each_data_service(&block)
                self
            end

            def find_port(name)
                find_input_port(name) || find_output_port(name)
            end

            def find_input_port(name)
                model.find_input_port(name)
            end

            def find_output_port(name)
                model.find_output_port(name)
            end

            def find_all_services_from_type(m)
                if self.model.fullfills?(m)
                    [self]
                else
                    []
                end
            end

            def config_type
                model.config_type
            end

            def has_output_port?(name)
                !!find_output_port(name)
            end

            def has_input_port?(name)
                !!find_input_port(name)
            end

            def each_input_port(with_slaves = false, &block)
                if !block_given?
                    return enum_for(:each_input_port, with_slaves)
                end

                model.each_input_port(&block)
                if with_slaves
                    each_slave do |name, srv|
                        srv.each_input_port(true, &block)
                    end
                end
            end

            def each_output_port(with_slaves = false, &block)
                if !block_given?
                    return enum_for(:each_output_port, with_slaves)
                end

                model.each_output_port(&block)
                if with_slaves
                    each_slave do |name, srv|
                        srv.each_output_port(true, &block)
                    end
                end
            end

            def each_task_input_port(with_slaves = false, &block)
                if !block_given?
                    return enum_for(:each_task_input_port, with_slaves)
                end

                mappings = port_mappings_for_task
                each_input_port do |port|
                    yield(component_model.find_input_port(mappings[port.name]))
                end
            end

            def each_task_output_port(with_slaves = false, &block)
                if !block_given?
                    return enum_for(:each_task_output_port, with_slaves)
                end

                mappings = port_mappings_for_task
                each_output_port do |port|
                    yield(component_model.find_output_port(mappings[port.name]))
                end
            end

            def each_slave(&block)
                component_model.each_slave_data_service(self, &block)
            end

            attr_reader :declared_dynamic_slaves

            def dynamic_slaves(source_model, options = Hash.new, &block)
                declared_dynamic_slaves << [source_model, block, model, options]
                source_model
            end

            def require_dynamic_slave(required_service, service_name, reason, component_model = nil)
                model, specialization_block, _ =
                    declared_dynamic_slaves.find do |model, specialization_block, _|
                        model == required_service
                    end

                return if !model

                component_model ||= self.component_model
                if !component_model.private_specialization?
                    component_model = component_model.
                        specialize("#{component_model.name}<#{reason}>")

                    SystemModel.debug { "created the specialized submodel #{component_model.short_name} of #{component_model.superclass.short_name} as a singleton model for #{reason}" }
                end

                service_model = required_service.
                    new_submodel(component_model.name + "." + required_service.short_name + "<" + service_name + ">")

                if specialization_block
                    service_model.apply_block(service_name, &specialization_block)
                end
                srv = component_model.require_dynamic_service(service_model, :as => service_name, :slave_of => name)

                return component_model, srv
            end

            def each_fullfilled_model
                model.ancestors.each do |m|
                    if m <= Component || m <= DataService
                        yield(m)
                    end
                end
            end

            # Helper class used by #add_slaves to provide the evaluation context
            class SlaveDefinitionContext
                def initialize(component_model, master_name)
                    @component_model = component_model
                    @master_name = master_name
                end

                def provides(*args, &block)
                    options =
                        if args.last.kind_of?(Hash)
                            args.pop
                        else Hash.new
                        end
                    options[:slave_of] = @master_name
                    args << options
                    @component_model.provides(*args, &block)
                end
            end

            # Provides an instanciation context that can be used to add multiple
            # slaves easily, e.g.:
            #
            # driver_for('NewDevice').add_slaves do
            #   provides Srv::Camera, :as => 'lcamera'
            #   provides Srv::Laser, :as => 'scans'
            #   ...
            # end
            #
            def add_slaves(&block)
                context = SlaveDefinitionContext.new(component_model, name)
                context.instance_eval(&block)
                self
            end

            # Returns the BoundDataService object that binds this provided
            # service to an actual task
            def bind(task)
                if !task.fullfills?(component_model)
                    raise ArgumentError, "cannot bind #{self} on #{task}: does not fullfill #{component_model}"
                end
                Syskit::BoundDataService.new(task, self)
            end

            def method_missing(m, *args, &block)
                if !args.empty? || block
                    return super
                end
                name = m.to_s
                if (name =~ /^(\w+)_srv$/) && (subservice = component_model.find_data_service("#{full_name}.#{$1}"))
                    return subservice
                elsif (name =~ /^(\w+)_port$/) && (p = find_port($1))
                    # We have to go through method missing as the representation
                    # of ports is a real REAL mess
                    return component_model.send("#{port_mappings[p.name] || p.name}_port")
                end
                super
            end
        end
    end
end
