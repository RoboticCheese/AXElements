framework 'ApplicationServices'

##
# [Reference](http://developer.apple.com/library/mac/#documentation/Carbon/Reference/QuartzEventServicesRef/Reference/reference.html).
#
# @todo Inertial scrolling
# @todo Bezier paths
# @todo More intelligent default duration
# @todo Refactor to try and reuse the same event for a single action
#       instead of creating new events.
# @todo Pause between down/up clicks
module Mouse
  extend self

  ##
  # Number of animation steps per second.
  #
  # @return [Number]
  FPS     = 120

  ##
  # @note We keep the number as a rational to try and avoid rounding
  #       error introduced by the way MacRuby deals with floats.
  #
  # Smallest unit of time allowed for an animation step.
  #
  # @return [Number]
  QUANTUM = Rational(1, FPS)

  ##
  # Available constants for the type of units to use when scrolling.
  #
  # @return [Hash{Symbol=>Fixnum}]
  UNIT = {
    line:  KCGScrollEventUnitLine,
    pixel: KCGScrollEventUnitPixel
  }

  ##
  # The coordinates of the mouse using the flipped coordinate system
  # (origin in top left).
  #
  # @return [CGPoint]
  def current_position
    CGEventGetLocation(CGEventCreate(nil))
  end

  ##
  # Move the mouse from the current position to the given point.
  #
  # @param [CGPoint]
  # @param [Float] duration animation duration, in seconds
  def move_to point, duration = 0.2
    animate KCGEventMouseMoved, KCGMouseButtonLeft, current_position, point, duration
  end

  ##
  # Click and drag from the current position to the given point.
  #
  # @param [CGPoint]
  # @param [Float] duration animation duration, in seconds
  def drag_to point, duration = 0.2
    post new_event(KCGEventLeftMouseDown, current_position, KCGMouseButtonLeft)

    animate KCGEventLeftMouseDragged, KCGMouseButtonLeft, current_position, point, duration

    post new_event(KCGEventLeftMouseUp, current_position, KCGMouseButtonLeft)
  end

  ##
  # @todo Need to double check to see if I introduce any inaccuracies.
  #
  # Scroll at the current position the given amount of units.
  #
  # Scrolling too much or too little in a period of time will cause the
  # animation to look weird, possibly causing the app to mess things up.
  #
  # @param [Fixnum] amount number of units to scroll; positive to scroll
  #   up or negative to scroll down
  # @param [Float] duration animation duration, in seconds
  # @param [Symbol] units `:line` scrolls by line, `:pixel` scrolls by pixel
  def scroll amount, duration = 0.2, units = :line
    units   = UNIT[units] || raise(ArgumentError, "#{units} is not a valid unit")
    steps   = (FPS * duration).round
    current = 0.0
    steps.times do |step|
      done     = (step+1).to_f / steps
      scroll   = ((done - current)*amount).floor
      post new_scroll_event(units, 1, scroll)
      sleep QUANTUM
      current += scroll.to_f / amount
    end
  end

  ##
  # A standard click. Default position is the current position.
  #
  # @param [CGPoint]
  def click point = current_position, duration = 12
    event = new_event KCGEventLeftMouseDown, point, KCGMouseButtonLeft
    post event
    duration.times { sleep QUANTUM }
    set event, to: KCGEventLeftMouseUp
    post event
  end

  ##
  # Standard secondary click. Default position is the current position.
  #
  # @param [CGPoint]
  def secondary_click point = current_position, duration = 12
    event = new_event KCGEventRightMouseDown, point, KCGMouseButtonRight
    post event
    duration.times { sleep QUANTUM }
    set event, to: KCGEventRightMouseUp
    post event
  end
  alias_method :right_click, :secondary_click

  ##
  # A standard double click. Defaults to clicking at the current position.
  #
  # @param [CGPoint]
  def double_click point = current_position
    event = new_event KCGEventLeftMouseDown, point, KCGMouseButtonLeft
    post event
    set  event, to: KCGEventLeftMouseUp
    post event

    CGEventSetIntegerValueField(event, KCGMouseEventClickState, 2)
    set  event, to: KCGEventLeftMouseDown
    post event
    set  event, to: KCGEventLeftMouseUp
    post event
  end

  ##
  # Click with an arbitrary mouse button, using numbers to represent
  # the mouse button. At the time of writing, the documented values are:
  #
  #  - KCGMouseButtonLeft   = 0
  #  - KCGMouseButtonRight  = 1
  #  - KCGMouseButtonCenter = 2
  #
  # And the rest are not documented! Though they should be easy enough
  # to figure out. See the `CGMouseButton` enum in the reference
  # documentation for the most up to date list.
  #
  # @param [CGPoint]
  # @param [Number]
  def arbitrary_click point = current_position, button = KCGMouseButtonCenter, duration = 12
    event = CGEventCreateMouseEvent(nil, KCGEventOtherMouseDown, point, button)
    CGEventPost(KCGHIDEventTap, event)
    duration.times do sleep QUANTUM end
    CGEventSetType(event, KCGEventOtherMouseUp)
    CGEventPost(KCGHIDEventTap, event)
  end
  alias_method :other_click, :arbitrary_click


  private

  ##
  # Executes a mouse movement animation. It can be a simple cursor
  # move or a drag depending on what is passed to `type`.
  def animate type, button, from, to, duration
    current = current_position
    xstep   = (to.x - current.x) / (FPS * duration)
    ystep   = (to.y - current.y) / (FPS * duration)
    start   = NSDate.date

    until close_enough?(current, to)
      remaining  = to.x - current.x
      current.x += xstep.abs > remaining.abs ? remaining : xstep

      remaining  = to.y - current.y
      current.y += ystep.abs > remaining.abs ? remaining : ystep

      post new_event(type, current, button)

      sleep QUANTUM
      break if NSDate.date.timeIntervalSinceDate(start) > 5.0
      current = current_position
    end
  end

  def close_enough? current, target
    x = current.x - target.x
    y = current.y - target.y
    delta = Math.sqrt((x**2) + (y**2))
    delta <= 1.0
  end

  def new_event event, position, button
    CGEventCreateMouseEvent(nil, event, position, button)
  end

  # @param [Fixnum] wheel which scroll wheel to use (value between 1-3)
  def new_scroll_event units, wheel, amount
    CGEventCreateScrollWheelEvent(nil, units, wheel, amount)
  end

  def post event
    CGEventPost(KCGHIDEventTap, event)
  end

  def set event, to: state
    CGEventSetType(event, state)
  end

end
