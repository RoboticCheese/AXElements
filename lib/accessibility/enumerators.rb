##
# Namespace for enumerators used to navigate accessibility hierarchies.
module Accessibility::Enumerators

  ##
  # Enumerator for visiting each element in a UI hierarchy in breadth
  # first order.
  class BreadthFirst
    include Enumerable

    # @param root [#children]
    def initialize root
      @root = root
    end

    ##
    # Semi-lazily iterate through the tree.
    #
    # @yield An element in the UI hierarchy
    # @yieldparam [AX::Element,AXUIElementRef]
    def each
      queue = [@root]
      until queue.empty?
        kids = queue.shift.children
        kids.each do |x| yield x end
        queue.concat kids
      end
    end

    ##
    # @note Explicitly defined so that escaping at the first found
    #       element actually works. Since only a single `break` is
    #       called when an item is found it does not fully escape the
    #       built in implementation. Technically, we need to do this
    #       with other 'escape-early' iteraters, but they aren't
    #       being used...yet.
    #
    # Override `Enumerable#find` for performance reasons.
    #
    # @yield An element in the UI hierarchy
    # @yieldparam [AX::Element,AXUIElementRef]
    def find
      each { |x| return x if yield x }
    end

  end

  ##
  # Enumerator for visitng each element in a UI hierarchy in
  # depth first order.
  class DepthFirst
    include Enumerable

    # @param root [#children]
    def initialize root
      @root = root
    end

    # @yield An element in the UI hierarchy
    # @yieldparam [AX::Element,AXUIElementRef]
    def each
      stack = @root.children
      until stack.empty?
        current = stack.shift
        yield current
        # needed to reverse, child ordering matters in practice
        stack.unshift *current.children
      end
    end

    ##
    # Walk the UI element tree and yield both the element and the
    # level that the element is at relative to the root.
    #
    # @yield An element in the UI hierarchy
    # @yieldparam [AX::Element,AXUIElementRef]
    # @yieldparam [Number]
    def each_with_level &block
      # @todo A bit of a hack that I would like to fix one day...
      @root.children.each do |element|
        recursive_each_with_level element, 1, block
      end
    end


    private

    ##
    # Recursive implementation of a depth first iterator.
    #
    # @param element [AX::Element]
    # @param depth [Number]
    # @param block [#call]
    def recursive_each_with_level element, depth, block
      block.call element, depth
      element.children.each do |x|
        recursive_each_with_level x, depth + 1, block
      end
    end

  end

end
