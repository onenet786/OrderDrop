window.LazyLoader = {
  loadedScripts: new Set(),

  load(scriptPath) {
    return new Promise((resolve, reject) => {
      if (this.loadedScripts.has(scriptPath)) {
        resolve();
        return;
      }

      const script = document.createElement('script');
      script.src = scriptPath;
      script.onload = () => {
        this.loadedScripts.add(scriptPath);
        resolve();
      };
      script.onerror = () => {
        reject(new Error(`Failed to load script: ${scriptPath}`));
      };

      document.head.appendChild(script);
    });
  },

  loadMultiple(scriptPaths) {
    return Promise.all(scriptPaths.map(path => this.load(path)));
  },

  async loadOnDemand(featureName, scriptPath, callback) {
    try {
      await this.load(scriptPath);
      if (callback && typeof callback === 'function') {
        callback();
      }
    } catch (error) {
      console.error(`Error loading ${featureName}:`, error);
    }
  }
};

window.LazyLoadStyles = {
  loadedStyles: new Set(),

  load(stylePath) {
    return new Promise((resolve, reject) => {
      if (this.loadedStyles.has(stylePath)) {
        resolve();
        return;
      }

      const link = document.createElement('link');
      link.rel = 'stylesheet';
      link.href = stylePath;
      link.onload = () => {
        this.loadedStyles.add(stylePath);
        resolve();
      };
      link.onerror = () => {
        reject(new Error(`Failed to load stylesheet: ${stylePath}`));
      };

      document.head.appendChild(link);
    });
  },

  loadMultiple(stylePaths) {
    return Promise.all(stylePaths.map(path => this.load(path)));
  }
};

window.deferredLoad = {
  queue: [],

  add(callback, delayMs = 1000) {
    setTimeout(() => {
      try {
        callback();
      } catch (error) {
        console.error('Error in deferred load callback:', error);
      }
    }, delayMs);
  },

  debounce(callback, delayMs = 1000) {
    let timeout;
    return function() {
      clearTimeout(timeout);
      timeout = setTimeout(callback, delayMs);
    };
  },

  throttle(callback, delayMs = 1000) {
    let lastCall = 0;
    return function() {
      const now = Date.now();
      if (now - lastCall >= delayMs) {
        lastCall = now;
        callback();
      }
    };
  }
};
