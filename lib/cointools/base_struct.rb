module CoinTools
  class BaseStruct
    def self.make(*fields)
      struct = Class.new(self)

      fields.each do |f|
        raise ArgumentError.new("Invalid field name: #{f}") unless f.to_s =~ /[a-z][a-z_]*/
      end

      struct.class_eval <<-CODE
        def initialize(#{fields.map { |f| "#{f}:" }.join(', ')})
          #{fields.map { |f| "@#{f} = #{f}" }.join("\n")}
        end

        attr_reader #{fields.map { |f| ":#{f}" }.join(', ')}
      CODE

      struct
    end
  end
end
