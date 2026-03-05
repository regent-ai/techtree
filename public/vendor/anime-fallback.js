(function initTechTreeAnimeFallback(global) {
  function normalizeTargets(targets) {
    if (!targets) return [];
    if (Array.isArray(targets)) return targets;
    if (typeof targets === "string") return Array.from(document.querySelectorAll(targets));
    if (targets instanceof NodeList) return Array.from(targets);
    return [targets];
  }

  function resolveValue(raw, index, total) {
    return typeof raw === "function" ? raw(null, index, total) : raw;
  }

  function animate(targets, options) {
    var elements = normalizeTargets(targets);
    var opts = options || {};
    var duration = Number(opts.duration || 480);
    var delayOption = opts.delay || 0;

    var run = Promise.all(
      elements.map(function (el, index) {
        var delay = Number(resolveValue(delayOption, index, elements.length) || 0);
        var keyframe = {};

        if (opts.opacity !== undefined) {
          keyframe.opacity = Array.isArray(opts.opacity) ? opts.opacity[1] : opts.opacity;
        }

        if (opts.translateY !== undefined) {
          var yValue = Array.isArray(opts.translateY) ? opts.translateY[1] : opts.translateY;
          keyframe.transform = "translateY(" + yValue + "px)";
        }

        if (opts.translateX !== undefined) {
          var xValue = Array.isArray(opts.translateX) ? opts.translateX[1] : opts.translateX;
          keyframe.transform = "translateX(" + xValue + "px)";
        }

        if (opts.scale !== undefined) {
          var sValue = Array.isArray(opts.scale) ? opts.scale[1] : opts.scale;
          keyframe.transform = "scale(" + sValue + ")";
        }

        var animation = el.animate([{}, keyframe], {
          duration: duration,
          delay: delay,
          easing: opts.ease || "ease-out",
          fill: "forwards"
        });

        return animation.finished.catch(function () {
          return null;
        });
      })
    );

    if (typeof opts.onComplete === "function") {
      run.finally(function () {
        opts.onComplete();
      });
    }

    return {
      finished: run,
      pause: function () {},
      play: function () {}
    };
  }

  function stagger(step, config) {
    var start = (config && config.start) || 0;
    return function (_, index) {
      return start + index * step;
    };
  }

  global.techTreeAnimeFallback = {
    animate: animate,
    stagger: stagger,
    createTimeline: function () {
      return {
        add: function (targets, options) {
          animate(targets, options);
          return this;
        }
      };
    }
  };
})(window);
