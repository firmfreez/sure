class DS::DateField < DesignSystemComponent
  attr_reader :form, :attribute, :value, :label, :remember, :input_options

  def initialize(form:, value:, label:, attribute: :date, remember: false, **input_options)
    @form = form
    @attribute = attribute
    @value = value
    @label = label
    @remember = remember
    @input_options = input_options
  end

  def field_options
    options = input_options.deep_dup
    data = options.delete(:data) || {}
    data[:DS__date_field_target] = "input"
    data[:action] = [ data[:action], "change->DS--date-field#remember" ].compact.join(" ")
    options.merge(value: value, label: label, data: data)
  end
end
