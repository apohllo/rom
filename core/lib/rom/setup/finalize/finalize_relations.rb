require 'rom/relation_registry'
require 'rom/mapper_registry'

module ROM
  class Finalize
    class FinalizeRelations
      attr_reader :notifications

      # Build relation registry of specified descendant classes
      #
      # This is used by the setup
      #
      # @param [Hash] gateways
      # @param [Array] relation_classes a list of relation descendants
      #
      # @api private
      def initialize(gateways, relation_classes, notifications:, mappers: nil, plugins: EMPTY_ARRAY)
        @gateways = gateways
        @relation_classes = relation_classes
        @mappers = mappers
        @plugins = plugins
        @notifications = notifications
      end

      # @return [Hash]
      #
      # @api private
      def run!
        relation_registry = RelationRegistry.new do |registry, relations|
          @relation_classes.each do |klass|
            key = klass.relation_name.to_sym

            if registry.key?(key)
              raise RelationAlreadyDefinedError,
                    "Relation with name #{key.inspect} registered more than once"
            end

            klass.use(:registry_reader, relation_names)

            relations[key] = build_relation(klass, registry)
          end

          registry.each do |_, relation|
            notifications.trigger(
              'configuration.relations.object.registered',
              relation: relation, registry: registry
            )
          end
        end

        notifications.trigger(
          'configuration.relations.registry.created', registry: relation_registry
        )

        relation_registry
      end

      # @return [ROM::Relation]
      #
      # @api private
      def build_relation(klass, registry)
        # TODO: raise a meaningful error here and add spec covering the case
        #       where klass' gateway points to non-existant repo
        gateway = @gateways.fetch(klass.gateway)

        if klass.schema_proc && !klass.schema
          plugins = schema_plugins

          resolved_schema = klass.schema_proc.call do
            plugins.each { |plugin| app_plugin(plugin) }
          end

          klass.set_schema!(resolved_schema)
        end

        notifications.trigger(
          'configuration.relations.schema.allocated',
          schema: klass.schema, gateway: gateway, registry: registry
        )

        relation_plugins.each do |plugin|
          plugin.apply_to(klass)
        end

        notifications.trigger(
          'configuration.relations.schema.set',
          schema: resolved_schema, relation: klass, adapter: klass.adapter
        )

        schema = klass.schema
        rel_key = schema.name.to_sym
        dataset = gateway.dataset(schema.name.dataset).instance_exec(klass, &klass.dataset)

        notifications.trigger(
          'configuration.relations.dataset.allocated',
          dataset: dataset, relation: klass, adapter: klass.adapter
        )

        mappers = @mappers.key?(rel_key) ? @mappers[rel_key] : MapperRegistry.new

        options = { __registry__: registry, mappers: mappers, schema: schema, **plugin_options }

        klass.new(dataset, options)
      end

      # @api private
      def plugin_options
        relation_plugins.map(&:config).map(&:to_hash).reduce(:merge) || EMPTY_HASH
      end

      # @api private
      def relation_plugins
        @plugins.select(&:relation?)
      end

      # @api private
      def schema_plugins
        @plugins.select(&:schema?)
      end

      # @api private
      def relation_names
        @relation_classes.map(&:relation_name).map(&:relation).uniq
      end
    end
  end
end
