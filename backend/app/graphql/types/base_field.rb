module Types
  class BaseField < GraphQL::Schema::Field
    argument_class Types::BaseArgument

    attr_reader :access

    def initialize(*args, access: nil, **kwargs, &block)
      @access = access.present? ? Array(access) : nil
      super(*args, **kwargs, &block)
    end

    def authorized?(object, args, context)
      super && permitted?(context)
    end

    private

    def permitted?(context)
      return true if access.blank? || access.include?(:public)

      access.intersect?(Array(context[:scopes]))
    end
  end
end
