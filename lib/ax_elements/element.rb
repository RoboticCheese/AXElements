# -*- coding: utf-8 -*-

require 'active_support/inflector'

##
# @abstract
#
# The abstract base class for all accessibility objects.
class AX::Element
  include Accessibility::PPInspector

  ##
  # Raised when a lookup fails
  class LookupFailure < ArgumentError
    def initialize name
      super "#{name} was not found"
    end
  end

  ##
  # Raised when trying to set an attribute that cannot be written
  class ReadOnlyAttribute < NoMethodError
    def initialize name
      super "#{name} is a read only attribute"
    end
  end

  ##
  # Raised when an implicit search fails
  class SearchFailure < NoMethodError
    def initialize searcher, searchee, filters
      path       = Accessibility.path(searcher).map { |x| x.inspect }
      pp_filters = (filters || {}).map do |key, value|
        "#{key}: #{value.inspect}"
      end.join(', ')
      msg  = "Could not find `#{searchee}"
      msg << "(#{pp_filters})" unless pp_filters.empty?
      msg << "` as a child of #{searcher.class}"
      msg << "\nElement Path:\n\t" << path.join("\n\t")
      super msg
    end
  end

  ##
  # @todo take a second argument of the attributes array; the attributes
  #       are already retrieved once to decide on the class type; if that
  #       can be cached and used to initialize an element, we can save a
  #       more expensive call to fetch the attributes
  #
  # @param [AXUIElementRef] element
  def initialize element
    @ref        = element
    @attributes = AX.attrs_of_element element
  end

  # @group Attributes

  ##
  # Cache of available attributes.
  #
  # @return [Array<String>]
  attr_reader :attributes

  # @param [Symbol] attr
  def attribute attr
    real_attr = attribute_for attr
    raise LookupFailure.new attr unless real_attr
    self.class.attribute_for @ref, real_attr
  end

  ##
  # Needed to override inherited {NSObject#description}. If you want a
  # description of the object use {#inspect} instead.
  def description
    attribute :description
  end

  ##
  # Get the process identifier for the application that the element
  # belongs to.
  #
  # @return [Fixnum]
  def pid
    @pid ||= AX.pid_of_element @ref
  end

  # @param [Symbol] attr
  def attribute_writable? attr
    real_attribute = attribute_for attr
    raise LookupFailure.new attr unless real_attribute
    AX.attr_of_element_writable? @ref, real_attribute
  end

  ##
  # We cannot make any assumptions about the state of the program after
  # you have set a value; at least not in the general case.
  #
  # @param [String] attr an attribute constant
  # @return the value that you set is returned
  def set_attribute attr, value
    raise ReadOnlyAttribute.new attr unless attribute_writable? attr
    real_attribute = attribute_for attr
    value = value.to_axvalue if value.kind_of? Boxed
    AX.set_attr_of_element @ref, real_attribute, value
    value
  end

  # @group Parameterized Attributes

  # @return [Array<String>] available parameterized attributes
  def param_attributes
    @param_attributes ||= AX.param_attrs_of_element @ref
  end

  # @param [Symbol] attr
  def param_attribute attr, param
    real_attr = param_attribute_for attr
    raise LookupFailure.new attr unless real_attr
    param = param.to_axvalue if param.kind_of? Boxed
    self.class.param_attribute_for @ref, real_attr, param
  end

  # @group Actions

  # @return [Array<String>] cache of available actions
  def actions
    AX.actions_of_element @ref # purposely not caching this array
  end

  ##
  # Ideally this method would return a reference to `self`, but since
  # this method inherently causes state change, the reference to `self`
  # may no longer be valid. An example of this would be pressing the
  # close button on a window.
  #
  # @param [String] name an action constant
  # @return [Boolean] true if successful
  def perform_action name
    real_action = action_for name
    raise LookupFailure.new name unless real_action
    AX.action_of_element @ref, real_action
  end

  # @group Search

  ##
  # Perform a breadth first search through the view hierarchy rooted at
  # the current element.
  #
  # See the {file:docs/Searching.markdown Searching} tutorial for the
  # details on searching.
  #
  # @example Find the dock item for the Finder app
  #
  #   AX::DOCK.search( :application_dock_item, title:'Finder' )
  #
  # @param [#to_s] element_type
  # @param [Hash{Symbol=>Object}] filters
  # @return [AX::Element,nil,Array<AX::Element>,Array<>]
  def search element_type, filters = nil
    type = element_type.to_s.camelize!
    meth = ((klass = type.singularize) == type) ? :find : :find_all
    Accessibility::Search.new(self).send(meth, klass, (filters || {}))
  end

  ##
  # We use {#method_missing} to dynamically handle requests to lookup
  # attributes or search for elements in the view hierarchy. An attribute
  # lookup is tried first.
  #
  # Failing both lookups, this method calls `super`.
  #
  # @example Attribute lookup of an element
  #
  #   mail   = AX::Application.application_with_bundle_identifier 'com.apple.mail'
  #   window = mail.focused_window
  #
  # @example Attribute lookup of an element property
  #
  #   window.title
  #
  # @example Simple single element search
  #
  #   window.button # => You want the first Button that is found
  #
  # @example Simple multi-element search
  #
  #   window.buttons # => You want all the Button objects found
  #
  # @example Filters for a single element search
  #
  #   window.button(title:'Log In') # => First Button with a title of 'Log In'
  #
  # @example Contrived multi-element search with filtering
  #
  #   window.buttons(title:'New Project', enabled:true)
  #
  # @example Attribute and element search failure
  #
  #   window.application # => SearchFailure is raised
  #
  def method_missing method, *args
    if attr = attribute_for(method)
      return self.class.attribute_for(@ref, attr)

    elsif attr = param_attribute_for(method)
      return self.class.param_attribute_for(@ref, attr, args.first)

    elsif self.respond_to? :children
      result = search method, args.first
      return result unless result.blank?
      raise SearchFailure.new(self, method, args.first)

    else
      super

    end
  end

  # @group Notifications

  ##
  # Register to receive a notification from an object.
  #
  # You can optionally pass a block to this method that will be given
  # an element equivalent to `self` and the name of the notification;
  # the block should return a truthy value that decides if the
  # notification received is the expected one.
  #
  # @param [String,Symbol] notif
  # @param [Float] timeout
  # @yieldparam [AX::Element] element
  # @yieldparam [String] notif
  # @yieldreturn [Boolean]
  # @return [Proc]
  def on_notification notif, &block
    AX.register_for_notif @ref, notif_for(notif) do |element, notif|
      element = self.class.process element
      block ? block.call(element, notif) : true
    end
  end

  # @endgroup

  ##
  # Overriden to produce cleaner output.
  def inspect
    msg  = "\#<#{self.class}" << pp_identifier
    msg << pp_position if attributes.include? KAXPositionAttribute
    msg << pp_children if attributes.include? KAXChildrenAttribute
    msg << pp_checkbox(:enabled) if attributes.include? KAXEnabledAttribute
    msg << pp_checkbox(:focused) if attributes.include? KAXFocusedAttribute
    msg << '>'
  end

  ##
  # Overriden to respond properly with regards to the dynamic
  # attribute lookups, but will return false on potential
  # search names.
  def respond_to? name
    return true if attribute_for name
    return true if param_attribute_for name
    super
  end

  ##
  # Get the position of the element, if it has one.
  #
  # @return [CGPoint]
  def to_point
    attribute(:position).center(attribute :size)
  end

  ##
  # Used during implicit search to determine if searches yielded
  # responses.
  def blank?
    false
  end

  ##
  # @todo Need to add '?' to predicate methods, but how?
  #
  # Like {#respond_to?}, this is overriden to include attribute methods.
  def methods include_super = true, include_objc_super = false
    names = attributes.map { |x| self.class.strip_prefix(x).underscore.to_sym }
    names + super
  end

  ##
  # Overridden so that equality testing would work. A hack, but the only
  # sane way I can think of to test for equivalency.
  def == other
    @ref == other.instance_variable_get(:@ref)
  end
  alias_method :eql?, :==
  alias_method :equal?, :==

  # @todo Do we need to override #=== as well?


  protected

  ##
  # Try to turn an arbitrary symbol into notification constant, and
  # then get the value of the constant.
  #
  # @param [Symbol]
  # @return [String]
  def notif_for name
    name  = name.to_s
    const = "KAX#{name.camelize!}Notification"
    Kernel.const_defined?(const) ? Kernel.const_get(const) : name
  end

  ##
  # Find the constant value for the given symbol. If nothing is found
  # then `nil` will be returned.
  #
  # @param [Symbol]
  # @return [String,nil]
  def attribute_for sym
    (@@array = attributes).find { |x| x == @@const_map[sym] }
  end

  # (see #attribute_for)
  def action_for sym
    (@@array = actions).find { |x| x == @@const_map[sym] }
  end

  # (see #attribute_for)
  def param_attribute_for sym
    (@@array = param_attributes).find { |x| x == @@const_map[sym] }
  end

  ##
  # Memoized map for symbols to constants used for attribute/action
  # lookups.
  #
  # @return [Hash{Symbol=>String}]
  @@const_map = Hash.new do |hash,key|
    @@array.map { |x| hash[strip_prefix(x).underscore.to_sym] = x }
    if hash.has_key? key
      hash[key]
    else # try other cases of transformations
      real_key = key.chomp('?').to_sym
      hash.has_key?(real_key) ? hash[key] = hash[real_key] : nil
    end
  end


  class << self

    ##
    # Retrieve and process the value of the given attribute for the
    # given element reference.
    #
    # @param [AXUIElementRef] ref
    # @param [String] attr
    def attribute_for ref, attr
      process AX.attr_of_element(ref, attr)
    end

    ##
    # Retrieve and process the value of the given parameterized attribute
    # for the parameter and given element reference.
    #
    # @param [AXUIElementRef] ref
    # @param [String] attr
    def param_attribute_for ref, attr, param
      param = param.to_axvalue if param.kind_of? Boxed
      process AX.param_attr_of_element(ref, attr, param)
    end

    ##
    # Meant for taking a return value from {AX.attr_of_element} and,
    # if required, converts the data to something more usable.
    #
    # Generally, used to process an AXValue into a CGPoint or an
    # AXUIElementRef into some kind of AX::Element object.
    def process value
      return nil if value.nil?
      id = ATTR_MASSAGERS[CFGetTypeID(value)]
      id ? self.send(id, value) : value
    end

    ##
    # @note In the case of a predicate name, this will strip the 'Is'
    #       part of the name if it is present
    #
    # Takes an accessibility constant and returns a new string with the
    # namespace prefix removed.
    #
    # @example
    #
    #   AX.strip_prefix 'AXTitle'                    # => 'Title'
    #   AX.strip_prefix 'AXIsApplicationEnabled'     # => 'ApplicationEnabled'
    #   AX.strip_prefix 'MCAXEnabled'                # => 'Enabled'
    #   AX.strip_prefix KAXWindowCreatedNotification # => 'WindowCreated'
    #   AX.strip_prefix NSAccessibilityButtonRole    # => 'Button'
    #
    # @param [String] const
    # @return [String]
    def strip_prefix const
      const.sub /^[A-Z]*?AX(?:Is)?/, ''
    end


    private

    ##
    # Map low level type ID numbers to methods. This is how we use
    # double dispatch to massage low-level data into something nice.
    #
    # @return [Array<Symbol>]
    ATTR_MASSAGERS = []
    ATTR_MASSAGERS[AXUIElementGetTypeID()] = :process_element
    ATTR_MASSAGERS[CFArrayGetTypeID()]     = :process_array
    ATTR_MASSAGERS[AXValueGetTypeID()]     = :process_box

    ##
    # @todo Refactor this pipeline so that we can pass the attributes we look
    #       up to the initializer for Element, and also so we can avoid some
    #       other duplicated work.
    #
    # Takes an AXUIElementRef and gives you some kind of accessibility object.
    #
    # @param [AXUIElementRef] element
    # @return [AX::Element]
    def process_element element
      roles = AX.roles_for(element).map! { |x| strip_prefix x }
      determine_class_for(roles).new(element)
    end

    ##
    # Like #const_get except that if the class does not exist yet then
    # it will assume the constant belongs to a class and creates the class
    # for you.
    #
    # @param [Array<String>] const the value you want as a constant
    # @return [Class] a reference to the class being looked up
    def determine_class_for names
      klass = names.first
      if AX.const_defined? klass, false
        AX.const_get klass
      else
        create_class *names
      end
    end

    ##
    # Creates new class at run time and puts it into the {AX} namespace.
    #
    # @param [String,Symbol] name
    # @param [String,Symbol] superklass
    # @return [Class]
    def create_class name, superklass = :Element
      real_superklass = determine_class_for [superklass]
      klass = Class.new real_superklass
      Accessibility.log.debug "#{name} class created"
      AX.const_set name, klass
    end

    ##
    # @todo Consider mapping in all cases to avoid returning a CFArray
    #
    # We assume a homogeneous array.
    #
    # @return [Array]
    def process_array vals
      return vals if vals.empty? || !ATTR_MASSAGERS[CFGetTypeID(vals.first)]
      vals.map { |val| process_element val }
    end

    ##
    # Extract the stuct contained in an AXValueRef.
    #
    # @param [AXValueRef] value
    # @return [Boxed]
    def process_box value
      box_type = AXValueGetType(value)
      ptr      = Pointer.new BOX_TYPES[box_type]
      AXValueGetValue(value, box_type, ptr)
      ptr[0]
    end

    # @return [String,nil] order-sensitive (which is why we unshift nil)
    BOX_TYPES = [CGPoint, CGSize, CGRect, CFRange].map! { |x| x.type }.unshift(nil)

  end
end

require 'ax_elements/elements/application'
require 'ax_elements/elements/systemwide'
require 'ax_elements/elements/row'
require 'ax_elements/elements/button'
require 'ax_elements/elements/static_text'
require 'ax_elements/elements/radio_button'
