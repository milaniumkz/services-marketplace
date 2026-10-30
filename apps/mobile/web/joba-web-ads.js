/* First-party bridge. No advertising network is contacted until explicit consent. */
(() => {
  let loading, rewardRunning = false;
  const validId = id => /^R-A-\d+-\d+$/.test(id);
  function sdk() {
    if (window.Ya?.Context?.AdvManager) return Promise.resolve(window.Ya.Context.AdvManager);
    if (loading) return loading;
    loading = new Promise((resolve, reject) => {
      window.yaContextCb = window.yaContextCb || [];
      const script = document.createElement('script');
      let settled = false;
      const finish = (error) => {
        if (settled) return; settled = true; clearTimeout(timer);
        if (error) { script.remove(); loading = undefined; reject(error); }
        else resolve(window.Ya.Context.AdvManager);
      };
      const timer = setTimeout(() => finish(new Error('Рекламная сеть не ответила. Попробуйте позже.')), 15000);
      window.yaContextCb.push(() => window.Ya?.Context?.AdvManager ? finish() : finish(new Error('Рекламная сеть недоступна.')));
      script.src = 'https://yandex.ru/ads/system/context.js'; script.async = true;
      script.dataset.jobaYandexAds = 'true';
      script.onerror = () => finish(new Error('Рекламу не удалось загрузить. Возможно, она заблокирована браузером.'));
      document.head.append(script);
    });
    return loading;
  }
  function connectedHost(id) {
    const current = document.getElementById(id);
    if (current?.isConnected) return Promise.resolve(current);
    return new Promise(resolve => {
      let done = false;
      const observer = new MutationObserver(() => {
        const host = document.getElementById(id);
        if (host?.isConnected) finish(host);
      });
      const finish = host => {
        if (done) return; done = true; observer.disconnect(); clearTimeout(timer); resolve(host);
      };
      const timer = setTimeout(() => finish(null), 5000);
      observer.observe(document.documentElement, {childList:true,subtree:true});
    });
  }
  function visibleHost(host) {
    if (typeof IntersectionObserver === 'undefined') return Promise.resolve(host.isConnected);
    return new Promise(resolve => {
      let done = false;
      const finish = visible => { if(done)return;done=true;visibility.disconnect();removal.disconnect();resolve(visible); };
      const visibility = new IntersectionObserver(entries => {if(entries.some(e=>e.isIntersecting&&e.intersectionRatio>=0.5))finish(true);}, {threshold:0.5});
      const removal = new MutationObserver(()=>{if(!host.isConnected)finish(false);});
      removal.observe(document.documentElement,{childList:true,subtree:true});visibility.observe(host);
    });
  }
  window.JobaWebAds = Object.freeze({
    async platform() { const manager = await sdk(); return manager.getPlatform() === 'desktop' ? 'desktop' : 'touch'; },
    async banner(elementId, blockId) {
      if (!validId(blockId)) throw new Error('Некорректный рекламный блок.');
      const manager = await sdk(), host = await connectedHost(elementId);
      if (!host?.isConnected || !await visibleHost(host)) return false;
      return await new Promise((resolve, reject) => {
        let settled = false;
        const finish = (shown, error) => {
          if (settled) return; settled = true; clearTimeout(timer);
          error ? reject(error) : resolve(shown === true);
        };
        const timer = setTimeout(() => finish(false), 30000);
        try { manager.render({ blockId, renderTo: elementId,
          onError: data => { if (data?.type !== 'warning') finish(false); },
          onRender: () => finish(true) });
        } catch (error) { finish(false, error); }
      });
    },
    async rewarded(blockId, platform) {
      if (!validId(blockId) || !['desktop','touch'].includes(platform)) throw new Error('Некорректный рекламный блок.');
      if (rewardRunning) throw new Error('Просмотр рекламы уже открыт.');
      rewardRunning = true;
      try {
        const manager = await sdk();
        return await new Promise((resolve, reject) => {
          let settled = false;
          const finish = (completed, error) => {
            if (settled) return; settled = true; clearTimeout(timer);
            error ? reject(error) : resolve(completed === true);
          };
          const timer = setTimeout(() => finish(false), 5 * 60 * 1000);
          try {
            manager.render({ blockId, type:'rewarded', platform,
              onRewarded: isRewarded => finish(isRewarded === true),
              onError: data => { if (data?.type !== 'warning') finish(false); } });
          } catch (error) { finish(false, error); }
        });
      } finally { rewardRunning = false; }
    }
  });
})();
