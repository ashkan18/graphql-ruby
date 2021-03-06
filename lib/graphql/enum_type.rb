# frozen_string_literal: true
module GraphQL
  # Represents a collection of related values.
  # By convention, enum names are `SCREAMING_CASE_NAMES`,
  # but other identifiers are supported too.
  #
  # You can use as return types _or_ as inputs.
  #
  # By default, enums are passed to `resolve` functions as
  # the strings that identify them, but you can provide a
  # custom Ruby value with the `value:` keyword.
  #
  # @example An enum of programming languages
  #   LanguageEnum = GraphQL::EnumType.define do
  #     name "Languages"
  #     description "Programming languages for Web projects"
  #     value("PYTHON", "A dynamic, function-oriented language")
  #     value("RUBY", "A very dynamic language aimed at programmer happiness")
  #     value("JAVASCRIPT", "Accidental lingua franca of the web")
  #   end
  #
  # @example Using an enum as a return type
  #    field :favoriteLanguage, LanguageEnum, "This person's favorite coding language"
  #    # ...
  #    # In a query:
  #    Schema.execute("{ coder(id: 1) { favoriteLanguage } }")
  #    # { "data" => { "coder" => { "favoriteLanguage" => "RUBY" } } }
  #
  # @example Defining an enum input
  #    field :coders, types[CoderType] do
  #      argument :knowing, types[LanguageEnum]
  #      resolve ->(obj, args, ctx) {
  #        Coder.where(language: args[:knowing])
  #      }
  #    end
  #
  # @example Using an enum as input
  #   {
  #     # find coders who know Python and Ruby
  #     coders(knowing: [PYTHON, RUBY]) {
  #       name
  #       hourlyRate
  #     }
  #   }
  #
  # @example Enum whose values are different in Ruby-land
  #   GraphQL::EnumType.define do
  #     # ...
  #     # use the `value:` keyword:
  #     value("RUBY", "Lisp? Smalltalk?", value: :rb)
  #   end
  #
  #   # Now, resolve functions will receive `:rb` instead of `"RUBY"`
  #   field :favoriteLanguage, LanguageEnum
  #   resolve ->(obj, args, ctx) {
  #     args[:favoriteLanguage] # => :rb
  #   }
  #
  # @example Enum whose values are different in ActiveRecord-land
  #   class Language < ActiveRecord::BaseType
  #     enum language: {
  #       rb: 0
  #     }
  #   end
  #
  #   # Now enum type should be defined as
  #   GraphQL::EnumType.define do
  #     # ...
  #     # use the `value:` keyword:
  #     value("RUBY", "Lisp? Smalltalk?", value: 'rb')
  #   end
  #

  class EnumType < GraphQL::BaseType
    accepts_definitions :values, value: GraphQL::Define::AssignEnumValue
    ensure_defined(:values, :validate_non_null_input, :coerce_non_null_input, :coerce_result)

    def initialize
      super
      @values_by_name = {}
    end

    def initialize_copy(other)
      super
      self.values = other.values.values
    end

    # @param new_values [Array<EnumValue>] The set of values contained in this type
    def values=(new_values)
      @values_by_name = {}
      new_values.each { |enum_value| add_value(enum_value) }
    end

    # @param enum_value [EnumValue] A value to add to this type's set of values
    def add_value(enum_value)
      if @values_by_name.key?(enum_value.name)
        raise "Enum value names must be unique. Value `#{enum_value.name}` already exists on Enum `#{name}`."
      end

      @values_by_name[enum_value.name] = enum_value
    end

    # @return [Hash<String => EnumValue>] `{name => value}` pairs contained in this type
    def values
      @values_by_name
    end

    def kind
      GraphQL::TypeKinds::ENUM
    end

    def coerce_result(value, ctx = nil)
      if ctx.nil?
        warn_deprecated_coerce("coerce_isolated_result")
        ctx = GraphQL::Query::NullContext
      end

      warden = ctx.warden
      all_values = warden ? warden.enum_values(self) : @values_by_name.each_value
      enum_value = all_values.find { |val| val.value == value }
      if enum_value
        enum_value.name
      else
        raise(UnresolvedValueError, "Can't resolve enum #{name} for #{value}")
      end
    end

    def to_s
      name
    end

    # A value within an {EnumType}
    #
    # Created with the `value` helper
    class EnumValue
      include GraphQL::Define::InstanceDefinable
      ATTRIBUTES = [:name, :description, :deprecation_reason, :value]
      accepts_definitions(*ATTRIBUTES)
      attr_accessor(*ATTRIBUTES)
      ensure_defined(*ATTRIBUTES)

      def name=(new_name)
        # Validate that the name is correct
        unless new_name =~ /^[_a-zA-Z][_a-zA-Z0-9]*$/
          raise(
            GraphQL::EnumType::InvalidEnumNameError,
            "Names must match /^[_a-zA-Z][_a-zA-Z0-9]*$/ but '#{new_name}' does not"
          )
        end

        @name = new_name
      end
    end

    class UnresolvedValueError < GraphQL::Error
    end

    class InvalidEnumNameError < GraphQL::Error
    end

    private

    # Get the underlying value for this enum value
    #
    # @example get episode value from Enum
    #   episode = EpisodeEnum.coerce("NEWHOPE")
    #   episode # => 6
    #
    # @param value_name [String] the string representation of this enum value
    # @return [Object] the underlying value for this enum value
    def coerce_non_null_input(value_name, ctx)
      if @values_by_name.key?(value_name)
        @values_by_name.fetch(value_name).value
      else
        nil
      end
    end

    def validate_non_null_input(value_name, ctx)
      result = GraphQL::Query::InputValidationResult.new
      allowed_values = ctx.warden.enum_values(self)
      matching_value = allowed_values.find { |v| v.name == value_name }

      if matching_value.nil?
        result.add_problem("Expected #{GraphQL::Language.serialize(value_name)} to be one of: #{allowed_values.map(&:name).join(', ')}")
      end

      result
    end
  end
end
