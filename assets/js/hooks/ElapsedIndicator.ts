import { PhoenixHook } from './PhoenixHook';

function formatParts(elapsedTimeMs: number): [number, string] {
  if (elapsedTimeMs < 1000) {
    return [elapsedTimeMs, 'ms'];
  } else if (elapsedTimeMs < 60 * 1000) {
    elapsedTimeMs = Math.floor(elapsedTimeMs / 1000);
    return [elapsedTimeMs, 's'];
  } else {
    elapsedTimeMs = Math.floor(elapsedTimeMs / 1000 / 60);
    return [elapsedTimeMs, 'm'];
  }
}

const ElapsedIndicator = {
  mounted() {
    this.updateTime();
    this.handle = setInterval(() => {
      this.updateTime();
    }, 1000);
  },
  updated() {
    this.updateTime();
  },
  destroyed() {
    clearInterval(this.handle);
  },
  updateTime() {
    const startTime = this.getStartTime();
    const finishTime = this.getFinishTime();

    if (startTime) {
      // select the appropriate unit based on elapsed time
      let elapsedTime = (finishTime || Date.now()) - startTime; // in milliseconds
      const [elapsedTimeNum, elapsedTimeUnit] = formatParts(elapsedTime);

      this.el.innerText = `${elapsedTimeNum} ${elapsedTimeUnit}`;
    } else {
      this.el.innerText = 'Not started';
    }
  },
  getFinishTime() {
    if (this.el.dataset.finishTime) {
      return Number(this.el.dataset.finishTime);
    }

    return false;
  },
  getStartTime() {
    if (this.el.dataset.startTime) {
      return Number(this.el.dataset.startTime);
    }

    return false;
  },
} as PhoenixHook<
  {
    handle: number;
    getStartTime(): number | false;
    getFinishTime(): number | false;
    updateTime(): void;
  },
  { startTime: string }
>;

export default ElapsedIndicator;
