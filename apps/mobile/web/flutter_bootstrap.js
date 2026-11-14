{{flutter_js}}
{{flutter_build_config}}

// API-backed screens must use the deployed release, not Flutter's retired
// offline app-shell cache. Only retire this application's root worker.
(async () => {
  if ('serviceWorker' in navigator) {
    try {
      const root = new URL('.', document.baseURI);
      const registrations = await navigator.serviceWorker.getRegistrations();
      let retiredController = false;
      for (const registration of registrations) {
        const worker = registration.active || registration.waiting || registration.installing;
        if (registration.scope !== root.href || !worker) continue;
        const script = new URL(worker.scriptURL);
        if (script.origin !== root.origin || script.pathname !== root.pathname + 'flutter_service_worker.js') continue;
        const controlsPage = navigator.serviceWorker.controller?.scriptURL === worker.scriptURL;
        if (await registration.unregister()) retiredController ||= controlsPage;
      }
      if (retiredController) {
        // Unregistration takes effect for a new document. No session storage,
        // authentication, drafts, or other applications' workers are removed.
        location.reload();
        return;
      }
      if ('caches' in window) {
        await Promise.all(['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest']
          .map(name => caches.delete(name)));
      }
    } catch (error) {
      console.warn('Could not retire the previous JOBA offline cache', error);
    }
  }
  _flutter.loader.load();
})();
