# frozen_string_literal: true

require "rom/registry"
require "rom/command_compiler"
require "rom/command_registry"

module ROM
  class Finalize
    class FinalizeCommands
      attr_reader :notifications

      attr_reader :inflector

      # Build command registry hash for provided relations
      #
      # @param [RelationRegistry] relations registry
      # @param [Hash] gateways
      # @param [Array] command_classes a list of command subclasses
      #
      # @api private
      def initialize(relations, gateways, command_classes, **options)
        @relations = relations
        @gateways = gateways
        @command_classes = command_classes
        @inflector = options.fetch(:inflector, Inflector)
        @notifications = options.fetch(:notifications)
      end

      # @return [Hash]
      #
      # @api private
      def run!
        commands = @command_classes.map do |klass|
          relation = @relations[klass.relation]
          gateway = @gateways[relation.gateway]

          notifications.trigger(
            "configuration.commands.class.before_build",
            command: klass, gateway: gateway, dataset: relation.dataset, adapter: relation.adapter
          )

          klass.build(
            relation.dataset,
            input: relation.input_schema,
            name: relation.name,
            gateway: relation.gateway
          )
        end

        registry = Registry.new
        compiler = CommandCompiler.new(
          @gateways,
          @relations,
          registry,
          notifications,
          inflector: inflector
        )

        @relations.each do |(name, relation)|
          rel_commands = commands.select { |c| c.dataset.eql?(relation.dataset) }

          rel_commands.each do |command|
            identifier = command.class.register_as || command.class.default_name
            relation.commands.elements[identifier] = command
          end

          relation.commands.set_compiler(compiler)
          relation.commands.set_mappers(relation.mappers)

          registry.elements[name] = relation.commands
        end

        registry
      end
    end
  end
end
