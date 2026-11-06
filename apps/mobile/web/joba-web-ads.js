/* First-party bridge. The network loads only for an active placement or user-started Rewarded. */
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
  let googleLoading;
  function googleSdk(client) {
    if (googleLoading) return googleLoading;
    googleLoading = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      let settled = false;
      const finish = error => {
        if (settled) return; settled = true; clearTimeout(timer);
        if (error) { script.remove(); googleLoading = undefined; reject(error); }
        else resolve();
      };
      const timer = setTimeout(() => finish(new Error('Google не ответил.')), 15000);
      script.async = true; script.crossOrigin = 'anonymous';
      script.src = 'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=' + client;
      script.onload = () => finish(); script.onerror = () => finish(new Error('Google недоступен.'));
      document.head.append(script);
    });
    return googleLoading;
  }
  async function googleBanner(elementId, client, slot, personalized) {
    if (!/^ca-pub-\d{16}$/.test(client) || !/^\d{10}$/.test(slot)) throw new Error('Некорректный блок Google.');
    const host = await connectedHost(elementId);
    if (!host?.isConnected || !await visibleHost(host)) return false;
    await googleSdk(client);
    if (!host.isConnected) return false;
    const ad = document.createElement('ins'); ad.className = 'adsbygoogle';
    Object.assign(ad.style, {display:'block',width:'100%',height:'50px'});
    ad.dataset.adClient = client; ad.dataset.adSlot = slot;
    ad.dataset.adFormat = 'horizontal'; ad.dataset.fullWidthResponsive = 'false';
    host.replaceChildren(ad);
    return await new Promise((resolve, reject) => {
      let settled = false;
      const finish = shown => {if(settled)return;settled=true;clearTimeout(timer);observer.disconnect();resolve(shown);};
      const observer = new MutationObserver(() => {
        if (ad.dataset.adStatus === 'filled') finish(true);
        if (ad.dataset.adStatus === 'unfilled' || !host.isConnected) finish(false);
      });
      observer.observe(ad,{attributes:true});
      const timer = setTimeout(() => finish(false),30000);
      try {
        window.adsbygoogle = window.adsbygoogle || [];
        window.adsbygoogle.requestNonPersonalizedAds = personalized === true ? 0 : 1;
        window.adsbygoogle.push({});
      } catch (error) {finish(false);}
    });
  }
  window.JobaWebAds = Object.freeze({
    googleBanner,
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
