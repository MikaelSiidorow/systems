// @ts-check

/**
 * @typedef {object} Departure
 * @property {number} serviceDay
 * @property {number} realtimeDeparture
 * @property {string} headsign
 * @property {{ route: { shortName: string } }} trip
 */

/**
 * @typedef {object} EntityAttributes
 * @property {Departure[]=} stoptimesWithoutPatterns
 * @property {string=} media_title
 * @property {string=} friendly_name
 * @property {string=} media_artist
 * @property {string=} media_series_title
 * @property {string=} app_name
 * @property {string=} source
 * @property {string=} entity_picture
 * @property {string=} media_image_url
 * @property {number=} media_duration
 * @property {number=} media_position
 * @property {string=} media_position_updated_at
 * @property {string=} unit_of_measurement
 * @property {number=} temperature
 * @property {string=} temperature_unit
 * @property {number=} apparent_temperature
 * @property {number|string=} high_temperature
 * @property {number|string=} low_temperature
 * @property {number|string=} precipitation_probability
 * @property {number|string=} precipitation
 * @property {CalendarEvent[]=} elsa_events
 * @property {CalendarEvent[]=} mikael_events
 */

/**
 * @typedef {object} CalendarEvent
 * @property {string} summary
 * @property {string} start
 * @property {string} end
 * @property {string=} location
 * @property {"elsa"|"mikael"=} owner
 */

/** @typedef {{ entity_id: string, state: string, last_changed: string, attributes: EntityAttributes }} HassEntity */
/** @typedef {{ s: string, lc?: number, lu: number }} HistoryState */
/** @typedef {{ states: Record<string, HassEntity>, callWS: (message: Record<string, unknown>) => Promise<unknown> }} HomeAssistant */
/** @typedef {{ entity: HassEntity, source: string, hasArtwork: boolean }} ActiveMedia */
/** @typedef {{ type: string, name: string, description: string, preview: boolean }} CustomCardRegistration */

const moduleUrl = new URL(import.meta.url);
const stylesheetUrl = new URL("./mythos-dashboard.css", moduleUrl);
stylesheetUrl.search = moduleUrl.search;
const wifiImageUrl = new URL("/local/mythos-wifi.png", moduleUrl);

const ENTITY = {
  departures: "sensor.pohjantori_departures",
  weather: "weather.home",
  weatherToday: "sensor.home_weather_today",
  agendaToday: "sensor.household_agenda_today",
  guestWifiQr: "input_boolean.guest_wifi_qr",
  chromecast: "media_player.living_room_tv",
  sonos: "media_player.sonos_ray",
  vacuum: "vacuum.exterminator",
  vacuumStatus: "sensor.exterminator_status",
  vacuumBattery: "sensor.exterminator_battery",
  vacuumProgress: "sensor.exterminator_cleaning_progress",
  vacuumArea: "sensor.exterminator_cleaning_area",
  vacuumTime: "sensor.exterminator_cleaning_time",
  vacuumNextRun: "sensor.exterminator_next_scheduled_cleaning",
  livingRoomTemperature: "sensor.living_room_temperature",
  livingRoomHumidity: "sensor.living_room_humidity",
  washingMachinePower: "sensor.washing_machine_plug_power",
  washingMachineRunning: "binary_sensor.washing_machine_running",
  pcPower: "sensor.pc_plug_power",
  pcRunning: "binary_sensor.pc_running",
};

const MEDIA_ACTIVE_STATES = new Set(["playing", "paused", "buffering"]);
const MISSING_STATES = new Set(["unknown", "unavailable", "none", ""]);
const WALK_TO_STOP_SECONDS = 2 * 60;
const RENDER_BATCH_MS = 100;

const REGION_DEPENDENCIES = {
  departures: [ENTITY.departures],
  weather: [ENTITY.weather, ENTITY.weatherToday],
  agenda: [ENTITY.agendaToday],
  wifi: [ENTITY.guestWifiQr],
  vacuum: [
    ENTITY.vacuum,
    ENTITY.vacuumStatus,
    ENTITY.vacuumBattery,
    ENTITY.vacuumProgress,
    ENTITY.vacuumArea,
    ENTITY.vacuumTime,
    ENTITY.vacuumNextRun,
  ],
  livingRoom: [ENTITY.livingRoomTemperature, ENTITY.livingRoomHumidity],
  washingMachine: [ENTITY.washingMachinePower, ENTITY.washingMachineRunning],
  pc: [ENTITY.pcPower, ENTITY.pcRunning],
  media: [ENTITY.chromecast, ENTITY.sonos],
};

const ALL_REGIONS = ["clock", ...Object.keys(REGION_DEPENDENCIES)];

class MythosDashboard extends HTMLElement {
  constructor() {
    super();
    const shadowRoot = this.attachShadow({ mode: "open" });
    shadowRoot.innerHTML = `
      <link rel="stylesheet" href="${stylesheetUrl.href}" />
      <div class="render-root">
        <div class="ambient-background" aria-hidden="true"></div>
        <main class="dashboard">
          <section class="primary-column">
            <header class="clock">
              <time data-value="time"></time>
              <div class="date" data-value="date"></div>
              <div class="agenda-slot" data-region="agenda"></div>
            </header>

            <section class="departures panel">
              <header>
                <div class="departures-title">
                  <ha-icon icon="mdi:bus-clock"></ha-icon>
                  <h1>Pohjantori <span>· E2052</span></h1>
                </div>
              </header>
              <div class="departure-list" data-region="departures"></div>
            </section>
          </section>

          <section class="secondary-column">
            <div class="weather-slot" data-region="weather"></div>
            <div class="wifi-slot" data-region="wifi"></div>
            <section class="status-strip">
              <div class="status-region" data-region="vacuum"></div>
              <div class="status-region" data-region="livingRoom"></div>
              <div class="status-region" data-region="washingMachine"></div>
              <div class="status-region" data-region="pc"></div>
            </section>
            <div class="media-slot" data-region="media"></div>
          </section>
        </main>
      </div>
    `;
    /** @type {HomeAssistant | null} */
    this._hass = null;
    /** @type {Map<string, string>} */
    this._regionMarkup = new Map();
    /** @type {Set<string>} */
    this._dirtyRegions = new Set(ALL_REGIONS);
    /** @type {number | undefined} */
    this._renderTimer = undefined;
    /** @type {number | undefined} */
    this._mediaProgressTimer = undefined;
    /** @type {number | undefined} */
    this._relativeTimeTimer = undefined;
    /** @type {Map<string, string>} */
    this._runningSince = new Map();
    /** @type {Set<string>} */
    this._runningHistoryPending = new Set();
    /** @type {string | null | undefined} */
    this._washingFinishedAt = undefined;
    this._washingCompletionPending = false;
  }

  /** @param {Record<string, unknown>} config */
  setConfig(config) {
    this._config = config;
    this.toggleAttribute("cast-view", config.cast_view === true);
    this.markDirty(ALL_REGIONS);
  }

  /** @param {HomeAssistant} hass */
  set hass(hass) {
    const previous = this._hass;
    this._hass = hass;
    const previousWashing = previous?.states[ENTITY.washingMachineRunning];
    const currentWashing = hass.states[ENTITY.washingMachineRunning];
    if (previousWashing?.state === "on" && currentWashing?.state === "off") {
      this._washingFinishedAt = currentWashing.last_changed;
    } else if (currentWashing?.state === "on") {
      this._washingFinishedAt = undefined;
    }
    this.syncRunningHistory();
    this.syncWashingCompletion();
    if (!previous) {
      this.markDirty(ALL_REGIONS);
      return;
    }

    for (const [region, entityIds] of Object.entries(REGION_DEPENDENCIES)) {
      if (entityIds.some((entityId) => previous.states[entityId] !== hass.states[entityId])) {
        this.markDirty([region]);
      }
    }
  }

  connectedCallback() {
    this._relativeTimeTimer = window.setInterval(
      () => this.markDirty(["clock", "departures", "agenda", "vacuum", "washingMachine", "pc"]),
      15_000,
    );
    this._mediaProgressTimer = window.setInterval(() => this.updateMediaProgress(), 1_000);
    this.markDirty(ALL_REGIONS);
  }

  disconnectedCallback() {
    if (this._relativeTimeTimer !== undefined) window.clearInterval(this._relativeTimeTimer);
    if (this._mediaProgressTimer !== undefined) window.clearInterval(this._mediaProgressTimer);
    if (this._renderTimer !== undefined) window.clearTimeout(this._renderTimer);
    this._relativeTimeTimer = undefined;
    this._mediaProgressTimer = undefined;
    this._renderTimer = undefined;
  }

  getCardSize() {
    return 1;
  }

  /** @param {string} entityId */
  entity(entityId) {
    return this._hass?.states?.[entityId];
  }

  /**
   * @param {HassEntity | undefined} entity
   * @returns {entity is HassEntity}
   */
  isAvailable(entity) {
    return entity !== undefined && !MISSING_STATES.has(entity.state);
  }

  syncRunningHistory() {
    const tracked = [
      [ENTITY.washingMachineRunning, "washingMachine"],
      [ENTITY.pcRunning, "pc"],
    ];
    for (const [entityId, region] of tracked) {
      if (this.entity(entityId)?.state !== "on") {
        this._runningSince.delete(entityId);
        continue;
      }
      if (!this._runningSince.has(entityId) && !this._runningHistoryPending.has(entityId)) {
        void this.loadRunningSince(entityId, region);
      }
    }
  }

  /** @param {string} entityId @param {string} region */
  async loadRunningSince(entityId, region) {
    if (!this._hass) return;
    this._runningHistoryPending.add(entityId);
    const startTime = new Date(Date.now() - 10 * 24 * 60 * 60 * 1_000);

    try {
      const response = /** @type {Record<string, HistoryState[]>} */ (
        await this._hass.callWS({
          type: "history/history_during_period",
          start_time: startTime.toISOString(),
          entity_ids: [entityId],
          include_start_time_state: true,
          significant_changes_only: true,
          minimal_response: true,
          no_attributes: true,
        })
      );
      const history = response[entityId] ?? [];
      let latestOn;
      for (let index = history.length - 1; index >= 0; index -= 1) {
        if (history[index].s === "on") {
          latestOn = history[index];
          break;
        }
      }
      const changedAt = latestOn?.lc ?? latestOn?.lu;
      const current = this.entity(entityId);
      if (current?.state === "on") {
        const startedAt =
          changedAt === undefined
            ? current.last_changed
            : new Date(changedAt * 1_000).toISOString();
        this._runningSince.set(entityId, startedAt);
        this.markDirty([region]);
      }
    } catch (error) {
      console.warn(`Unable to load running history for ${entityId}`, error);
      const current = this.entity(entityId);
      if (current?.state === "on") this._runningSince.set(entityId, current.last_changed);
    } finally {
      this._runningHistoryPending.delete(entityId);
    }
  }

  syncWashingCompletion() {
    if (
      this.entity(ENTITY.washingMachineRunning)?.state === "off" &&
      this._washingFinishedAt === undefined &&
      !this._washingCompletionPending
    ) {
      void this.loadWashingCompletion();
    }
  }

  async loadWashingCompletion() {
    if (!this._hass) return;
    this._washingCompletionPending = true;
    const entityId = ENTITY.washingMachineRunning;
    const startTime = new Date(Date.now() - 10 * 24 * 60 * 60 * 1_000);

    try {
      const response = /** @type {Record<string, HistoryState[]>} */ (
        await this._hass.callWS({
          type: "history/history_during_period",
          start_time: startTime.toISOString(),
          entity_ids: [entityId],
          include_start_time_state: true,
          significant_changes_only: true,
          minimal_response: true,
          no_attributes: true,
        })
      );
      const history = response[entityId] ?? [];
      let latestOff;
      for (let index = history.length - 1; index >= 0; index -= 1) {
        if (history[index].s === "off") {
          latestOff = history[index];
          break;
        }
      }
      const changedAt = latestOff?.lc ?? latestOff?.lu;
      if (this.entity(entityId)?.state === "off") {
        this._washingFinishedAt =
          changedAt === undefined ? null : new Date(changedAt * 1_000).toISOString();
        this.markDirty(["washingMachine"]);
      }
    } catch (error) {
      console.warn("Unable to load washing machine completion history", error);
      this._washingFinishedAt = null;
    } finally {
      this._washingCompletionPending = false;
    }
  }

  /** @param {unknown} value */
  escape(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  /** @param {string} name @param {string} markup */
  updateRegion(name, markup) {
    if (!this.shadowRoot || this._regionMarkup.get(name) === markup) return false;
    const region = this.shadowRoot.querySelector(`[data-region="${name}"]`);
    if (!(region instanceof HTMLElement)) return false;
    region.innerHTML = markup;
    this._regionMarkup.set(name, markup);
    return true;
  }

  /** @param {string} name @param {string} value */
  updateValue(name, value) {
    const element = this.shadowRoot?.querySelector(`[data-value="${name}"]`);
    if (element && element.textContent !== value) element.textContent = value;
  }

  /** @param {string[]} regions */
  markDirty(regions) {
    for (const region of regions) this._dirtyRegions.add(region);
    if (!this.isConnected || this._renderTimer !== undefined) return;
    this._renderTimer = window.setTimeout(() => {
      this._renderTimer = undefined;
      this.flushRender();
    }, RENDER_BATCH_MS);
  }

  /** @param {Date} now */
  renderDepartures(now) {
    const sensor = this.entity(ENTITY.departures);
    const departures = sensor?.attributes?.stoptimesWithoutPatterns ?? [];
    const buses = departures
      .filter((departure) => ["111", "113"].includes(departure?.trip?.route?.shortName))
      .slice(0, 3);

    if (buses.length === 0) {
      return '<div class="empty-state">No upcoming 111 or 113 departures</div>';
    }

    const firstCatchableIndex = buses.findIndex((departure) => {
      const timestamp = (departure.serviceDay + departure.realtimeDeparture) * 1000;
      return (timestamp - now.getTime()) / 1000 >= WALK_TO_STOP_SECONDS;
    });

    return buses
      .map((departure, index) => {
        const timestamp = (departure.serviceDay + departure.realtimeDeparture) * 1000;
        const seconds = Math.max(0, Math.round((timestamp - now.getTime()) / 1000));
        const minutes = Math.ceil(seconds / 60);
        const relative = seconds <= 30 ? "Now" : seconds < 90 ? "~1 min" : `${minutes} min`;
        const absolute = new Intl.DateTimeFormat("en-FI", {
          hour: "2-digit",
          minute: "2-digit",
          hour12: false,
        })
          .format(timestamp)
          .replace(":", ".");
        const destination = departure.headsign.replaceAll(" (M)", "");
        const unreachable = seconds < WALK_TO_STOP_SECONDS;
        const recommended = index === firstCatchableIndex;

        return `
          <div class="departure-row ${unreachable ? "unreachable" : ""} ${recommended ? "recommended" : ""}">
            <div class="route-block">
              <div class="route">${this.escape(departure.trip.route.shortName)}</div>
              <div class="destination">${this.escape(destination)}</div>
            </div>
            <div class="departure-time">
              <strong>${relative}</strong>
              <span>${absolute}</span>
            </div>
          </div>
        `;
      })
      .join("");
  }

  renderWeather() {
    const weather = this.entity(ENTITY.weather);
    if (!this.isAvailable(weather) || weather.attributes.temperature === undefined) return "";

    const today = this.entity(ENTITY.weatherToday);
    const temperature = Number(weather.attributes.temperature).toLocaleString("en-FI", {
      maximumFractionDigits: 0,
    });
    const unit = weather.attributes.temperature_unit ?? "°C";
    /** @type {Record<string, string>} */
    const conditionLabels = {
      "clear-night": "Clear night",
      cloudy: "Cloudy",
      fog: "Fog",
      hail: "Hail",
      lightning: "Lightning",
      "lightning-rainy": "Thunderstorms",
      partlycloudy: "Partly cloudy",
      pouring: "Heavy rain",
      rainy: "Rainy",
      snowy: "Snowy",
      "snowy-rainy": "Sleet",
      sunny: "Sunny",
      windy: "Windy",
      "windy-variant": "Windy",
    };
    const displayCondition = conditionLabels[weather.state] ?? weather.state.replaceAll("-", " ");
    const high = Number(today?.attributes.high_temperature);
    const low = Number(today?.attributes.low_temperature);
    const rainProbability = Number(today?.attributes.precipitation_probability);
    const precipitation = Number(today?.attributes.precipitation);
    const hasRange = Number.isFinite(high) && Number.isFinite(low);
    const hasRainProbability = Number.isFinite(rainProbability);
    const hasPrecipitation = Number.isFinite(precipitation) && precipitation > 0;
    /** @type {Record<string, string>} */
    const conditionIcons = {
      "clear-night": "mdi:weather-night",
      cloudy: "mdi:weather-cloudy",
      fog: "mdi:weather-fog",
      hail: "mdi:weather-hail",
      lightning: "mdi:weather-lightning",
      "lightning-rainy": "mdi:weather-lightning-rainy",
      partlycloudy: "mdi:weather-partly-cloudy",
      pouring: "mdi:weather-pouring",
      rainy: "mdi:weather-rainy",
      snowy: "mdi:weather-snowy",
      "snowy-rainy": "mdi:weather-snowy-rainy",
      sunny: "mdi:weather-sunny",
      windy: "mdi:weather-windy",
      "windy-variant": "mdi:weather-windy-variant",
    };
    const conditionIcon = conditionIcons[weather.state] ?? "mdi:weather-cloudy-alert";

    return `
      <section class="weather-feature" aria-label="Today's weather">
        <div class="weather-current">
          <strong>${this.escape(temperature)}<span>${this.escape(unit)}</span></strong>
          <div class="weather-condition">${this.escape(displayCondition)}</div>
          <ha-icon class="weather-condition-icon" icon="${conditionIcon}"></ha-icon>
        </div>
        ${
          hasRange
            ? `<div class="weather-range"><span><strong>${high.toLocaleString("en-FI", { maximumFractionDigits: 0 })}°</strong> high</span><span><strong>${low.toLocaleString("en-FI", { maximumFractionDigits: 0 })}°</strong> low</span></div>`
            : ""
        }
        ${
          hasRainProbability
            ? `<div class="weather-rain"><ha-icon icon="mdi:weather-rainy"></ha-icon><span><strong>${rainProbability.toLocaleString("en-FI", { maximumFractionDigits: 0 })} %</strong> rain today${hasPrecipitation ? ` · ${precipitation.toLocaleString("en-FI", { maximumFractionDigits: 1 })} mm` : ""}</span></div>`
            : ""
        }
      </section>
    `;
  }

  renderWifi() {
    if (this.entity(ENTITY.guestWifiQr)?.state !== "on") return "";
    return `
      <aside class="wifi-card panel">
        <div class="eyebrow">Wi-Fi</div>
        <img src="${wifiImageUrl.href}" alt="Mythos Wi-Fi QR code" />
      </aside>
    `;
  }

  /** @param {string} value */
  parseCalendarDate(value) {
    if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
      const [year, month, day] = value.split("-").map(Number);
      return new Date(year, month - 1, day);
    }
    return new Date(value.includes("T") ? value : value.replace(" ", "T"));
  }

  /** @param {Date} now */
  renderAgenda(now) {
    const agenda = this.entity(ENTITY.agendaToday);
    const elsaEvents = agenda?.attributes.elsa_events ?? [];
    const mikaelEvents = agenda?.attributes.mikael_events ?? [];
    const rawEvents = [
      ...elsaEvents.map((event) => ({ ...event, owner: "elsa" })),
      ...mikaelEvents.map((event) => ({ ...event, owner: "mikael" })),
    ];

    const uniqueEvents = new Map();
    for (const event of rawEvents) {
      if (!event || typeof event !== "object") continue;
      const calendarEvent = /** @type {CalendarEvent} */ (event);
      if (!calendarEvent.summary || !calendarEvent.start || !calendarEvent.end) continue;
      const key = `${calendarEvent.summary}\u0000${calendarEvent.start}\u0000${calendarEvent.end}`;
      uniqueEvents.set(key, calendarEvent);
    }

    const events = [...uniqueEvents.values()]
      .map((event) => {
        const start = this.parseCalendarDate(event.start);
        const end = this.parseCalendarDate(event.end);
        const allDay = /^\d{4}-\d{2}-\d{2}$/.test(event.start);
        return { event, start, end, allDay };
      })
      .filter(({ start, end }) => !Number.isNaN(start.getTime()) && !Number.isNaN(end.getTime()))
      .sort((left, right) => left.start.getTime() - right.start.getTime());

    const todayStart = new Date(now);
    todayStart.setHours(0, 0, 0, 0);
    const tomorrowStart = new Date(todayStart);
    tomorrowStart.setDate(tomorrowStart.getDate() + 1);
    const dayAfterTomorrow = new Date(tomorrowStart);
    dayAfterTomorrow.setDate(dayAfterTomorrow.getDate() + 1);

    /**
     * @param {typeof events[number]} item
     * @param {Date} dayStart
     * @param {Date} dayEnd
     * @param {Date} notBefore
     */
    const relevantOn = (item, dayStart, dayEnd, notBefore) => {
      if (item.start >= dayEnd || item.end <= dayStart || item.end <= notBefore) return false;
      const isWeekday = dayStart.getDay() >= 1 && dayStart.getDay() <= 5;
      if (!isWeekday || item.allDay) return true;
      const eveningStart = new Date(dayStart);
      eveningStart.setHours(16, 0, 0, 0);
      return item.end > eveningStart;
    };

    const todayEvents = events.filter((item) => relevantOn(item, todayStart, tomorrowStart, now));
    const tomorrowEvents = events.filter((item) =>
      relevantOn(item, tomorrowStart, dayAfterTomorrow, tomorrowStart),
    );
    const showingTomorrow = todayEvents.length === 0 && tomorrowEvents.length > 0;
    const selectedEvents = showingTomorrow ? tomorrowEvents : todayEvents;
    if (selectedEvents.length === 0) return "";

    const visibleEvents = selectedEvents.slice(0, 2);
    const hiddenCount = selectedEvents.length - visibleEvents.length;
    const isWeekday = now.getDay() >= 1 && now.getDay() <= 5;
    const heading = showingTomorrow ? "Tomorrow" : isWeekday ? "Tonight" : "Today";

    const rows = visibleEvents
      .map(({ event, start, end, allDay }) => {
        const active = !showingTomorrow && !allDay && start <= now && end > now;
        const time = allDay
          ? "All day"
          : active
            ? "Now"
            : new Intl.DateTimeFormat("en-FI", {
                hour: "2-digit",
                minute: "2-digit",
                hour12: false,
              })
                .format(start)
                .replace(":", ".");
        return `
          <li class="agenda-event owner-${event.owner}">
            <time>${this.escape(time)}</time>
            <span>${this.escape(event.summary)}</span>
          </li>
        `;
      })
      .join("");

    return `
      <section class="agenda" aria-label="${heading} events">
        <header><ha-icon icon="mdi:calendar-today"></ha-icon>${heading}</header>
        <ol>${rows}</ol>
        ${hiddenCount > 0 ? `<div class="agenda-more">+${hiddenCount} more</div>` : ""}
      </section>
    `;
  }

  /** @returns {ActiveMedia | null} */
  activeMedia() {
    const chromecast = this.entity(ENTITY.chromecast);
    const castDescription = [
      chromecast?.attributes.app_name,
      chromecast?.attributes.media_title,
      chromecast?.attributes.media_series_title,
    ]
      .filter(Boolean)
      .join(" ")
      .toLocaleLowerCase();
    const isInformationDisplay = ["home assistant", "information display"].some((label) =>
      castDescription.includes(label),
    );
    if (chromecast && MEDIA_ACTIVE_STATES.has(chromecast.state) && !isInformationDisplay) {
      return {
        entity: chromecast,
        source: "Chromecast",
        hasArtwork: Boolean(
          chromecast.attributes.entity_picture || chromecast.attributes.media_image_url,
        ),
      };
    }

    const sonos = this.entity(ENTITY.sonos);
    if (sonos && this.isAvailable(sonos) && !["off", "idle"].includes(sonos.state)) {
      return {
        entity: sonos,
        source: "Sonos Ray",
        hasArtwork: Boolean(sonos.attributes.entity_picture || sonos.attributes.media_image_url),
      };
    }

    return null;
  }

  /** @param {ActiveMedia | null} media */
  renderMedia(media) {
    if (!media) return "";

    const attributes = media.entity.attributes ?? {};
    const title = attributes.media_title || attributes.friendly_name || "Now playing";
    const detail =
      attributes.media_artist ||
      attributes.media_series_title ||
      attributes.app_name ||
      attributes.source ||
      "";
    const image = attributes.entity_picture || attributes.media_image_url;
    const imageUrl = image ? new URL(image, moduleUrl).href : "";
    const distinctDetail = detail.toLocaleLowerCase() === title.toLocaleLowerCase() ? "" : detail;
    const duration = Number(attributes.media_duration);
    const hasTimeline = Number.isFinite(duration) && duration > 0;
    const playbackLabel =
      media.entity.state === "paused"
        ? "Paused"
        : media.entity.state === "buffering"
          ? "Buffering"
          : "Now playing";

    return `
      <section class="media ${media.hasArtwork ? "with-artwork" : "compact"} panel">
        ${imageUrl ? `<div class="artwork"><img src="${this.escape(imageUrl)}" alt="" /></div>` : ""}
        <div class="media-copy">
          <div class="eyebrow">${playbackLabel} · ${this.escape(media.source)}</div>
          <div class="media-title">${this.escape(title)}</div>
          ${distinctDetail ? `<div class="media-detail">${this.escape(distinctDetail)}</div>` : ""}
          ${
            hasTimeline
              ? `<div class="media-progress">
                  <div class="media-progress-track"><div class="media-progress-fill" data-media-progress></div></div>
                  <div class="media-progress-times">
                    <span data-media-elapsed></span>
                    <span data-media-remaining></span>
                  </div>
                </div>`
              : ""
          }
        </div>
      </section>
    `;
  }

  /** @param {number} seconds */
  formatMediaTime(seconds) {
    const total = Math.max(0, Math.floor(seconds));
    const minutes = Math.floor(total / 60);
    return `${minutes}:${String(total % 60).padStart(2, "0")}`;
  }

  updateMediaProgress() {
    const media = this.activeMedia();
    if (!media || !this.shadowRoot) return;

    const attributes = media.entity.attributes;
    const duration = Number(attributes.media_duration);
    let position = Number(attributes.media_position);
    if (!Number.isFinite(duration) || duration <= 0 || !Number.isFinite(position)) return;

    const updatedAt = Date.parse(attributes.media_position_updated_at ?? "");
    if (media.entity.state === "playing" && Number.isFinite(updatedAt)) {
      position += Math.max(0, (Date.now() - updatedAt) / 1_000);
    }
    position = Math.min(duration, Math.max(0, position));

    const progress = this.shadowRoot.querySelector("[data-media-progress]");
    const elapsed = this.shadowRoot.querySelector("[data-media-elapsed]");
    const remaining = this.shadowRoot.querySelector("[data-media-remaining]");
    if (progress instanceof HTMLElement) {
      progress.style.transform = `scaleX(${position / duration})`;
    }
    if (elapsed) elapsed.textContent = this.formatMediaTime(position);
    if (remaining) remaining.textContent = `−${this.formatMediaTime(duration - position)}`;
  }

  renderVacuum() {
    const statusEntity = this.entity(ENTITY.vacuumStatus);
    const batteryEntity = this.entity(ENTITY.vacuumBattery);
    const vacuumEntity = this.entity(ENTITY.vacuum);
    const nextRunEntity = this.entity(ENTITY.vacuumNextRun);
    const status = this.isAvailable(statusEntity)
      ? statusEntity.state.replaceAll("_", " ")
      : "Offline";
    const displayStatus = status.charAt(0).toLocaleUpperCase() + status.slice(1);
    const battery = this.isAvailable(batteryEntity) ? `${batteryEntity.state} %` : "";
    const isCleaning = vacuumEntity?.state === "cleaning";

    let cleaningDetail = "";
    let displayValue = displayStatus;
    if (isCleaning) {
      const progress = this.entity(ENTITY.vacuumProgress);
      const area = this.entity(ENTITY.vacuumArea);
      const time = this.entity(ENTITY.vacuumTime);
      const progressNumber = Number(progress?.state);
      if (this.isAvailable(progress) && Number.isFinite(progressNumber)) {
        displayValue = `${progressNumber.toLocaleString("en-FI", { maximumFractionDigits: 0 })} %`;
      } else {
        displayValue = "Cleaning";
      }

      /** @param {HassEntity | undefined} entity @param {string} fallbackUnit */
      const formatReading = (entity, fallbackUnit) => {
        if (!this.isAvailable(entity)) return "";
        const number = Number(entity.state);
        const value = Number.isFinite(number)
          ? number.toLocaleString("en-FI", { maximumFractionDigits: 0 })
          : entity.state;
        return `${value} ${entity.attributes.unit_of_measurement ?? fallbackUnit}`;
      };
      cleaningDetail = [formatReading(area, "m²"), formatReading(time, "min")]
        .filter(Boolean)
        .join(" · ");
    }

    let nextRun = "Schedule unavailable";
    if (this.isAvailable(nextRunEntity)) {
      const parsed = new Date(nextRunEntity.state);
      if (!Number.isNaN(parsed.getTime())) {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const scheduledDay = new Date(parsed);
        scheduledDay.setHours(0, 0, 0, 0);
        const calendarDay = (date) =>
          Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86_400_000;
        const daysAway = calendarDay(scheduledDay) - calendarDay(today);
        const day =
          daysAway === 0
            ? "Today"
            : daysAway === 1
              ? "Tomorrow"
              : new Intl.DateTimeFormat("en-FI", { weekday: "short" }).format(parsed);
        const time = new Intl.DateTimeFormat("en-FI", {
          hour: "2-digit",
          minute: "2-digit",
          hour12: false,
        })
          .format(parsed)
          .replace(":", ".");
        nextRun = `${day} · ${time}`;
      }
    }

    const attention = !["charging", "docked", "idle"].includes(status.toLocaleLowerCase());
    const detail = cleaningDetail || nextRun;

    return `
      <article class="metric vacuum-compact ${attention ? "attention" : ""}">
        <div>
          <div class="metric-label vacuum-label"><ha-icon icon="mdi:robot-vacuum"></ha-icon>${battery ? this.escape(battery) : ""}</div>
          <div class="metric-value">${this.escape(displayValue)}</div>
          <div class="metric-detail">${this.escape(detail)}</div>
        </div>
      </article>
    `;
  }

  renderLivingRoom() {
    const temperature = this.entity(ENTITY.livingRoomTemperature);
    const humidity = this.entity(ENTITY.livingRoomHumidity);
    if (!this.isAvailable(temperature) && !this.isAvailable(humidity)) return "";

    const temperatureValue = this.isAvailable(temperature)
      ? `${Number(temperature.state).toLocaleString("en-FI", { maximumFractionDigits: 1 })} ${temperature.attributes.unit_of_measurement ?? "°C"}`
      : "Temperature unavailable";
    const humidityValue = this.isAvailable(humidity)
      ? `${Number(humidity.state).toLocaleString("en-FI", { maximumFractionDigits: 0 })} ${humidity.attributes.unit_of_measurement ?? "%"} humidity`
      : "";

    return `
      <article class="metric">
        <div>
          <div class="metric-label">Living room</div>
          <div class="metric-value">${this.escape(temperatureValue)}</div>
          ${humidityValue ? `<div class="metric-detail">${this.escape(humidityValue)}</div>` : ""}
        </div>
      </article>
    `;
  }

  /**
   * @param {string} powerEntityId
   * @param {string} runningEntityId
   * @param {string} label
   * @param {number} fallbackThreshold
   * @param {boolean=} showCompletion
   */
  renderPowerMetric(
    powerEntityId,
    runningEntityId,
    label,
    fallbackThreshold,
    showCompletion = false,
  ) {
    const powerEntity = this.entity(powerEntityId);
    const runningEntity = this.entity(runningEntityId);
    if (!this.isAvailable(powerEntity)) return "";

    const power = Number(powerEntity.state);
    const unit = powerEntity.attributes.unit_of_measurement ?? "W";
    const running = this.isAvailable(runningEntity)
      ? runningEntity.state === "on"
      : Number.isFinite(power) && power > fallbackThreshold;
    if (!running) {
      if (!showCompletion || !this._washingFinishedAt) return "";
      const minutesAgo = Math.floor(
        (Date.now() - new Date(this._washingFinishedAt).getTime()) / 60_000,
      );
      if (!Number.isFinite(minutesAgo) || minutesAgo < 0 || minutesAgo >= 60) return "";
      const completed = minutesAgo < 1 ? "Just now" : `${minutesAgo} min ago`;
      return `
        <article class="metric attention">
          <div>
            <div class="metric-label">${this.escape(label)}</div>
            <div class="metric-value">Done</div>
            <div class="metric-detail">${this.escape(completed)}</div>
          </div>
        </article>
      `;
    }

    const elapsed = this.formatElapsed(
      this._runningSince.get(runningEntityId) ??
        (this.isAvailable(runningEntity) ? runningEntity.last_changed : null),
    );
    const value = `${power.toLocaleString("en-FI", { maximumFractionDigits: 1 })} ${unit}`;

    return `
      <article class="metric attention">
        <div>
          <div class="metric-label">${this.escape(label)}</div>
          <div class="metric-value">${this.escape(value)}</div>
          ${elapsed ? `<div class="metric-detail">Running for ${this.escape(elapsed)}</div>` : ""}
        </div>
      </article>
    `;
  }

  /** @param {string | null} changedAt */
  formatElapsed(changedAt) {
    if (!changedAt) return "";
    const minutes = Math.max(0, Math.floor((Date.now() - new Date(changedAt).getTime()) / 60_000));
    if (minutes < 1) return "<1 min";
    if (minutes < 60) return `${minutes} min`;
    const hours = Math.floor(minutes / 60);
    const remainder = minutes % 60;
    return remainder ? `${hours} h ${remainder} min` : `${hours} h`;
  }

  flushRender() {
    if (!this._hass) return;
    const dirty = new Set(this._dirtyRegions);
    this._dirtyRegions.clear();
    const now = new Date();

    if (dirty.has("clock")) {
      const timeParts = new Intl.DateTimeFormat("en-FI", {
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
      }).formatToParts(now);
      /** @param {string} type */
      const timePart = (type) => timeParts.find((item) => item.type === type)?.value ?? "00";
      this.updateValue("time", `${timePart("hour")}.${timePart("minute")}`);
      const weekday = new Intl.DateTimeFormat("en-FI", { weekday: "long" }).format(now);
      const month = new Intl.DateTimeFormat("en-US", { month: "short" }).format(now);
      this.updateValue("date", `${weekday} ${now.getDate()} ${month}`);
    }
    if (dirty.has("weather")) this.updateRegion("weather", this.renderWeather());
    if (dirty.has("wifi")) this.updateRegion("wifi", this.renderWifi());
    if (dirty.has("agenda")) this.updateRegion("agenda", this.renderAgenda(now));
    if (dirty.has("departures")) {
      this.updateRegion("departures", this.renderDepartures(now));
    }
    if (dirty.has("vacuum")) this.updateRegion("vacuum", this.renderVacuum());
    if (dirty.has("livingRoom")) {
      this.updateRegion("livingRoom", this.renderLivingRoom());
    }
    if (dirty.has("washingMachine")) {
      this.updateRegion(
        "washingMachine",
        this.renderPowerMetric(
          ENTITY.washingMachinePower,
          ENTITY.washingMachineRunning,
          "Washing machine",
          3,
          true,
        ),
      );
    }
    if (dirty.has("pc")) {
      this.updateRegion("pc", this.renderPowerMetric(ENTITY.pcPower, ENTITY.pcRunning, "PC", 15));
    }

    const media = this.activeMedia();
    if (dirty.has("media")) this.updateRegion("media", this.renderMedia(media));
    if (dirty.has("media")) this.updateMediaProgress();
  }
}

if (!customElements.get("mythos-dashboard")) {
  customElements.define("mythos-dashboard", MythosDashboard);
}

/** @type {Window & typeof globalThis & { customCards?: CustomCardRegistration[] }} */
const dashboardWindow = window;
dashboardWindow.customCards ??= [];
dashboardWindow.customCards.push({
  type: "mythos-dashboard",
  name: "Mythos information display",
  description: "Read-only household information display",
  preview: false,
});
