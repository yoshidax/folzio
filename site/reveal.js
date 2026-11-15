// Fades the screenshots in as they scroll into view. With reduced motion, videos do not play by themselves.
// Without JavaScript or IntersectionObserver, or with reduced motion, the screenshots are shown as they are.
(function () {
  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var canObserve = 'IntersectionObserver' in window;
  if (canObserve && !reduceMotion) {
    // Set before the body is parsed, so the screenshots do not appear and then disappear.
    document.documentElement.classList.add('reveal-ready');
  }

  document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('video.shot').forEach(function (video) {
      if (reduceMotion) {
        video.removeAttribute('autoplay');
        video.pause();
      }
    });

    if (!canObserve || reduceMotion) {
      return;
    }
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    }, { rootMargin: '0px 0px -10% 0px', threshold: 0.15 });

    document.querySelectorAll('.shot').forEach(function (element) {
      if (element.closest('.hero')) {
        // The hero screenshot is part of the first view, so it fades in on load instead of waiting for a scroll.
        requestAnimationFrame(function () {
          requestAnimationFrame(function () { element.classList.add('is-visible'); });
        });
      } else {
        observer.observe(element);
      }
    });
  });
})();
