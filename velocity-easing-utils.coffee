VelocityEasingUtils =
  _inverseEasing: (easing) ->
    # Given a monotonic easing function mapping time to progress, return the inverse, mapping progress to time
    return (progress) ->
      if progress == 0
        return 0
      if progress == 1
        return 1
      lo = 0
      hi = 1
      while hi - lo > 1e-6
          mid = (lo + hi) / 2
          if easing(mid) < progress
              lo = mid
          else
              hi = mid
      return lo

  _renormalizedEasing: (easing, fromDuration, toDuration) ->
    # Creates a new easing with correct domain/range using an interval of an existing easing
    fromProgress = easing(fromDuration)
    toProgress = easing(toDuration)
    return (itemTime) ->
      # Scale the time from [0, 1] to [fromDuration, toDuration]
      sequenceTime = (itemTime * (toDuration - fromDuration)) + fromDuration
      # Call the original easing with the time. This should result in a progress value in [fromProgress, toProgress]
      sequenceProgress = easing(sequenceTime)
      # Scale the progress from [fromProgress, toProgress] to [0, 1]
      itemProgress = (sequenceProgress - fromProgress) / (toProgress - fromProgress)
      return itemProgress

  _composeEasing: (easing1, easing2) ->
    return (args...) -> easing1(easing2(args...))

  _getDuration: (item) ->
    options = item.o || item.options || $.Velocity.defaults
    return if 'duration' of options then options.duration else $.Velocity.defaults.duration

  sequenceWithOptions: (sequence, { easing, duration, debugCanvas }) ->
    console.assert(easing)
    console.assert(easing of $.Velocity.Easings, "String easing only") # TODO support velocity's other types of easing
    easingFunc = $.Velocity.Easings[easing]
    totalWeight = sequence.reduce(((sum, item) -> sum + VelocityEasingUtils._getDuration(item)), 0)
    duration ?= totalWeight

    cumulativeWeight = 0
    return sequence.map((item, i) ->
      options = item.o || item.options
      console.assert(not options?.sequenceQueue, 'Sequential animations only') # TODO support sequenceQueue

      # Find out how much progress this item represents
      weight = VelocityEasingUtils._getDuration(item)
      fromProgress = cumulativeWeight / totalWeight
      toProgress = (cumulativeWeight + weight) / totalWeight
      cumulativeWeight += weight

      # Figure out when this item should run and for how long based on the easing
      fromDuration = VelocityEasingUtils._inverseEasing(easingFunc)(fromProgress)
      toDuration = VelocityEasingUtils._inverseEasing(easingFunc)(toProgress)
      itemDuration = duration * (toDuration - fromDuration)

      # Construct the easing for this part of the animation
      customEasingName = "#{easing}-#{fromDuration}-#{toDuration}"
      customEasing = VelocityEasingUtils._renormalizedEasing(easingFunc, fromDuration, toDuration)
      optionsEasingName = options?.easing
      console.assert(not optionsEasingName or optionsEasingName of $.Velocity.Easings, "String easing only") # TODO support velocity's other types of easing

      optionsEasing = $.Velocity.Easings[optionsEasingName]
      if optionsEasing
        customEasingName = "${optionsEasingName}-#{customEasingName}"
        $.Velocity.Easings[customEasingName] = VelocityEasingUtils._composeEasing(customEasing, optionsEasing)
      else
        # TODO should/might still need to compose with $.Velocity.defaults.easing?
        $.Velocity.Easings[customEasingName] = customEasing

      # Replace the existing easing, duration, and progress options with the ones computed
      optionsProgressCallback = options?.progress
      newOptions = {
        easing: customEasingName,
        duration: itemDuration,
        progress:
          if not debugCanvas
            optionsProgressCallback
          else
            (e, percent, rest...) ->
              window.requestAnimationFrame(->
                VelocityEasingUtils.drawEasingGraph(
                  debugCanvas,
                  easingFunc,
                  fromDuration + (toDuration - fromDuration) * percent,
                  fromDuration,
                  toDuration,
                  ['red', 'orange', 'yellow', 'green', 'blue', 'indigo', 'violet'][i % 7]
                )
                optionsProgressCallback?(e, percent, rest...)
              )
      }
      if item.options
        item.options = $.extend({}, item.options, newOptions)
      else
        item.o = $.extend({}, item.o, newOptions)

      return item
    )

  drawEasingGraph: (canvas, easing, currentDuration = null, fromDuration = 0, toDuration = 1, color = 'black') ->
    if typeof easing == 'string'
      easing = $.Velocity.Easings[easing]
    canvas = $(canvas)[0]
    context = canvas.getContext('2d')

    margin = 30
    width = canvas.width - 2 * margin
    height = canvas.height - 2 * margin

    currentProgress = easing(currentDuration)
    fromProgress = easing(fromDuration)
    toProgress = easing(toDuration)

    context.clearRect(0, 0, canvas.width, canvas.height)

    # Draw horizontal grid
    context.strokeStyle = '#636363'
    context.lineWidth = 1
    context.beginPath()
    context.moveTo(margin, margin + height - height * fromProgress)
    context.lineTo(margin + width * fromDuration, margin + height - height * fromProgress)
    context.stroke()
    context.beginPath()
    context.moveTo(margin, margin + height - height * toProgress)
    context.lineTo(margin + width * toDuration, margin + height - height * toProgress)
    context.stroke()

    # Draw vertical grid
    context.strokeStyle = '#eee'
    context.lineWidth = 1
    context.beginPath()
    context.moveTo(margin + width * fromDuration, margin + height)
    context.lineTo(margin + width * fromDuration, margin + height - height * fromProgress)
    context.stroke()
    context.beginPath()
    context.moveTo(margin + width * toDuration, margin + height)
    context.lineTo(margin + width * toDuration, margin + height - height * toProgress)
    context.stroke()

    # Draw axes
    context.strokeStyle = 'black'
    context.lineWidth = 2
    context.beginPath()
    context.moveTo(margin, margin)
    context.lineTo(margin, margin + height)
    context.lineTo(margin + width, margin + height)
    context.stroke()

    # Draw labels
    lineHeight = 12
    context.font = "#{lineHeight}px Arial"
    context.fillStyle = '#636363'
    context.textAlign = 'center'
    context.save()
    context.translate(margin + width / 2, margin + height + margin / 2)
    context.fillText('Time', 0, lineHeight / 2)
    context.restore()
    context.save()
    context.translate(margin / 2, margin + height / 2)
    context.rotate(-Math.PI / 2)
    context.fillText('Progress', 0, lineHeight / 2)
    context.restore()

    # Draw arrow indicating current time
    if currentDuration?
      arrowSize = 6
      context.fillStyle = '#636363'
      context.beginPath()
      context.moveTo(margin + width * currentDuration, margin + height)
      context.lineTo(margin + width * currentDuration - 3, margin + height + arrowSize)
      context.lineTo(margin + width * currentDuration + 3, margin + height + arrowSize)
      context.fill()

    # Draw easing function
    context.strokeStyle = 'black'
    context.lineWidth = 2
    context.beginPath()
    context.moveTo(margin, margin + height)
    for x in [0 .. width]
      context.lineTo(margin + x, margin + height - height * easing(x / width))
      if x == Math.round(width * fromDuration)
        context.stroke()
        context.strokeStyle = color
        context.lineWidth = 5
        context.beginPath()
        context.moveTo(margin + x, margin + height - height * easing(x / width))
      if x == Math.round(width * currentDuration)
        context.stroke()
        context.strokeStyle = 'black'
        context.lineWidth = 2
        context.beginPath()
        context.moveTo(margin + x, margin + height - height * easing(x / width))
    context.stroke()
