// Enlarges a screenshot or video to the full viewport width when it is clicked.
// The backdrop dims the page; Escape or a click on the backdrop zooms it back out and fades it away.
(function () {
  var DURATION = 450;
  var EASE = 'cubic-bezier(0.22, 1, 0.36, 1)';
  var japanese = document.documentElement.lang === 'ja';
  var enlargeLabel = japanese ? '拡大: ' : 'Enlarge: ';
  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  var open = null;
  // Keys that scroll the page. The scrollbar stays visible while the view is open, so the layout never shifts;
  // instead, these inputs are ignored until the view closes.
  var SCROLL_KEYS = [' ', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'PageUp', 'PageDown', 'Home', 'End'];

  function blockScroll(event) {
    if (open) {
      event.preventDefault();
    }
  }
  document.addEventListener('wheel', blockScroll, { passive: false });
  document.addEventListener('touchmove', blockScroll, { passive: false });

  function viewport() {
    return { width: document.documentElement.clientWidth, height: window.innerHeight };
  }

  // Fill the viewport width; when that would be taller than the viewport, fit the height instead.
  function targetRect(aspect) {
    var view = viewport();
    var width = view.width;
    var height = width / aspect;
    if (height > view.height) {
      height = view.height;
      width = height * aspect;
    }
    return { left: (view.width - width) / 2, top: (view.height - height) / 2, width: width, height: height };
  }

  function transformFrom(from, to) {
    var scale = from.width / to.width;
    return 'translate(' + (from.left - to.left) + 'px, ' + (from.top - to.top) + 'px) scale(' + scale + ')';
  }

  function copyMedia(source) {
    var copy;
    if (source.tagName === 'VIDEO') {
      copy = document.createElement('video');
      copy.muted = true;
      copy.loop = true;
      copy.playsInline = true;
      copy.poster = source.poster;
      copy.src = source.currentSrc || source.querySelector('source').src;
      copy.addEventListener('loadedmetadata', function () {
        copy.currentTime = source.currentTime;
        if (!source.paused) {
          copy.play();
        }
      }, { once: true });
      // Inside the enlarged view, a click pauses or resumes the video.
      copy.addEventListener('click', function (event) {
        event.stopPropagation();
        if (copy.paused) {
          copy.play();
        } else {
          copy.pause();
        }
      });
    } else {
      copy = document.createElement('img');
      copy.src = source.currentSrc || source.src;
      copy.alt = source.alt;
      copy.addEventListener('click', function (event) { event.stopPropagation(); });
    }
    copy.className = 'lightbox-media';
    return copy;
  }

  function show(source) {
    if (open) {
      return;
    }
    var from = source.getBoundingClientRect();
    var to = targetRect(from.width / from.height);
    var animate = !reduceMotion.matches;

    var layer = document.createElement('div');
    layer.className = 'lightbox';
    layer.setAttribute('role', 'dialog');
    layer.setAttribute('aria-modal', 'true');
    layer.setAttribute('aria-label', source.getAttribute('alt') || source.getAttribute('aria-label') || '');
    layer.tabIndex = -1;
    var media = copyMedia(source);
    media.style.left = to.left + 'px';
    media.style.top = to.top + 'px';
    media.style.width = to.width + 'px';
    media.style.height = to.height + 'px';
    if (animate) {
      media.style.transform = transformFrom(from, to);
    }
    layer.appendChild(media);
    document.body.appendChild(layer);
    source.style.visibility = 'hidden';

    open = { source: source, layer: layer, media: media, closing: false };
    layer.addEventListener('click', hide);
    layer.focus({ preventScroll: true });

    // Start from the original position, then let the transitions run on the next frame.
    requestAnimationFrame(function () {
      requestAnimationFrame(function () {
        layer.classList.add('is-open');
        if (animate) {
          media.style.transition = 'transform ' + DURATION + 'ms ' + EASE + ', opacity ' + DURATION + 'ms ' + EASE;
          media.style.transform = 'none';
        }
      });
    });
  }

  function hide() {
    if (!open || open.closing) {
      return;
    }
    var current = open;
    current.closing = true;
    var animate = !reduceMotion.matches;
    var finished = false;
    function finish() {
      if (finished) {
        return;
      }
      finished = true;
      current.layer.remove();
      current.source.style.visibility = '';
      current.source.focus({ preventScroll: true });
      open = null;
    }

    current.layer.classList.remove('is-open');
    if (animate) {
      var to = current.media.getBoundingClientRect();
      var from = current.source.getBoundingClientRect();
      current.media.style.transform = transformFrom(from, to);
      current.media.style.opacity = '0';
      // Fall back to a timer in case transitionend does not arrive.
      setTimeout(finish, DURATION + 100);
      current.media.addEventListener('transitionend', finish, { once: true });
    } else {
      finish();
    }
  }

  document.addEventListener('keydown', function (event) {
    if (!open) {
      return;
    }
    if (event.key === 'Escape') {
      event.preventDefault();
      hide();
    } else if (event.key === 'Tab' || SCROLL_KEYS.indexOf(event.key) !== -1) {
      // The enlarged view is the only thing to focus while it is open, and the page does not scroll behind it.
      event.preventDefault();
    }
  });

  document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('.shot').forEach(function (element) {
      element.tabIndex = 0;
      element.setAttribute('role', 'button');
      element.setAttribute('aria-label', enlargeLabel + (element.getAttribute('alt') || element.getAttribute('aria-label') || ''));
      element.addEventListener('click', function () { show(element); });
      element.addEventListener('keydown', function (event) {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          show(element);
        }
      });
    });
  });
})();
