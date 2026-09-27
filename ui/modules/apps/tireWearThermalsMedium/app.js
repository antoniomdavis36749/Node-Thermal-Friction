angular.module("beamng.apps")
    .directive("tireWearThermalsMedium", ["$injector", function ($injector) {
        return {
            template: `
                <div class="ttm-panel-container">
                    <style>
                        .ttm-panel-container {
                            width: 100%;
                            height: 100%;
                            max-height: 100%;
                            min-height: 0;
                            background: rgba(18, 22, 28, 0.52);
                            border: 1px solid rgba(255, 255, 255, 0.06);
                            border-radius: 6px;
                            box-sizing: border-box;
                            font-family: "Lucida Console", Monaco, monospace;
                            color: #f1f5f9;
                            overflow-x: hidden;
                            overflow-y: auto;
                            -webkit-overflow-scrolling: touch;
                            padding: 8px;
                            pointer-events: auto;
                        }
                        .ttm-header {
                            display: flex;
                            justify-content: space-between;
                            align-items: center;
                            border-bottom: 2px solid rgba(255, 255, 255, 0.08);
                            padding-bottom: 5px;
                            margin-bottom: 8px;
                        }
                        .ttm-title {
                            font-size: 12px;
                            font-weight: bold;
                            letter-spacing: 1.2px;
                            color: #38bdf8;
                        }
                        .ttm-grid {
                            display: grid;
                            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
                            gap: 8px;
                        }
                        .ttm-card {
                            background: rgba(30, 41, 59, 0.38);
                            border: 1px solid rgba(255, 255, 255, 0.04);
                            border-radius: 5px;
                            padding: 8px;
                            box-sizing: border-box;
                        }
                        .ttm-card-header {
                            display: flex;
                            justify-content: space-between;
                            align-items: center;
                            border-bottom: 1px solid rgba(255, 255, 255, 0.08);
                            padding-bottom: 4px;
                            margin-bottom: 6px;
                        }
                        .ttm-wheel-name {
                            font-size: 12px;
                            font-weight: bold;
                            color: #38bdf8;
                        }
                        .ttm-compound-tag {
                            font-size: 9px;
                            background: rgba(56, 189, 248, 0.12);
                            border: 1px solid rgba(56, 189, 248, 0.2);
                            padding: 1px 5px;
                            border-radius: 3px;
                            text-transform: uppercase;
                            letter-spacing: 0.4px;
                        }
                        .ttm-stat-row {
                            display: flex;
                            justify-content: space-between;
                            margin-bottom: 3px;
                            font-size: 10px;
                        }
                        .ttm-label { color: #94a3b8; }
                        .ttm-value { font-weight: bold; }
                        .ttm-section-label {
                            font-size: 9px;
                            color: #94a3b8;
                            margin-top: 5px;
                            margin-bottom: 1px;
                        }
                        .ttm-thermal-strip {
                            display: grid;
                            grid-template-columns: repeat(3, 1fr);
                            gap: 3px;
                            margin: 3px 0 5px;
                            height: 20px;
                        }
                        .ttm-thermal-segment {
                            display: flex;
                            align-items: center;
                            justify-content: center;
                            font-size: 10px;
                            font-weight: bold;
                            border-radius: 3px;
                            text-shadow: 1px 1px 1px rgba(0,0,0,0.85);
                        }
                        /* A3: Classic-style O|M|I remaining tread (vertical fill) */
                        .ttm-zone-strip {
                            display: grid;
                            grid-template-columns: repeat(3, 1fr);
                            gap: 4px;
                            margin: 3px 0 6px;
                        }
                        .ttm-zone-col {
                            display: flex;
                            flex-direction: column;
                            align-items: center;
                            gap: 2px;
                        }
                        .ttm-zone-bar-bg {
                            width: 100%;
                            height: 36px;
                            background: rgba(15, 23, 42, 0.65);
                            border-radius: 3px;
                            overflow: hidden;
                            display: flex;
                            flex-direction: column;
                            justify-content: flex-end;
                            border: 1px solid rgba(255, 255, 255, 0.06);
                            box-sizing: border-box;
                        }
                        .ttm-zone-bar-fill {
                            width: 100%;
                            min-height: 0;
                        }
                        .ttm-zone-pct {
                            font-size: 9px;
                            font-weight: bold;
                        }
                        .ttm-bar-container {
                            width: 100%;
                            background: rgba(255, 255, 255, 0.05);
                            border-radius: 3px;
                            height: 5px;
                            overflow: hidden;
                            margin-top: 2px;
                        }
                        .ttm-bar-fill {
                            height: 100%;
                        }
                        .ttm-diagnostics-grid {
                            display: grid;
                            grid-template-columns: 1fr 1fr 1fr;
                            gap: 6px;
                            border-top: 1px dashed rgba(255, 255, 255, 0.08);
                            margin-top: 6px;
                            padding-top: 6px;
                        }
                        .ttm-diagnostic-item { font-size: 9px; }
                        .ttm-diag-label {
                            color: #64748b;
                            display: block;
                            margin-bottom: 2px;
                            font-size: 8px;
                            letter-spacing: 0.4px;
                        }
                    </style>

                    <div class="ttm-header">
                        <span class="ttm-title">NODE-THERMAL FRICTION · CREW</span>
                    </div>

                    <div ng-if="!wheels.length" class="ttm-waiting"
                         style="padding: 18px 12px; text-align: center; color: #94a3b8; font-size: 11px; line-height: 1.45;">
                        <div style="color: #e2e8f0; margin-bottom: 6px;">Waiting for tire stream…</div>
                        Spawn or <b>respawn</b> the vehicle.<br/>
                        Enable <b>core</b> Node-Thermal Friction (Compat tires alone is not enough).
                    </div>

                    <div class="ttm-grid" ng-if="wheels.length">
                        <div class="ttm-card" ng-repeat="w in wheels">
                            <div class="ttm-card-header">
                                <span class="ttm-wheel-name">{{ w.name }}</span>
                                <span class="ttm-compound-tag">{{ formatProfile(w.profile) }}</span>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Cond %:</span>
                                <span class="ttm-value" ng-style="{'color': getConditionColor(w.condition)}">
                                    {{ (w.condition !== undefined ? w.condition : 0).toFixed(0) }}%
                                    <span style="font-size: 10px; opacity: 0.75; margin-left: 4px;">
                                        sc {{ (w.conditionScalar !== undefined ? w.conditionScalar : w.condition || 0).toFixed(0) }}%
                                        · nd {{ (w.conditionNode !== undefined ? w.conditionNode : (100 - (w.nodeWearPeak||0)*100)).toFixed(0) }}%
                                    </span>
                                </span>
                            </div>
                            <div class="ttm-cap-dim" style="margin: -2px 0 4px 0; font-size: 10px; opacity: 0.7;">
                                Cond = min(sc,nd) · A2 fades from sc · node μ owns grip feel
                            </div>
                            <div class="ttm-bar-container" style="margin-bottom: 5px;">
                                <div class="ttm-bar-fill" ng-style="{'width': (w.condition || 0) + '%', 'background-color': getConditionColor(w.condition)}"></div>
                            </div>

                            <div class="ttm-section-label">Tread Zones (O | M | I):</div>
                            <div class="ttm-zone-strip">
                                <div class="ttm-zone-col" ng-repeat="zc in w.zoneCondition track by $index">
                                    <div class="ttm-zone-bar-bg">
                                        <div class="ttm-zone-bar-fill"
                                             ng-style="{'height': zoneFillHeight(zc), 'background-color': getConditionColor(zc)}"></div>
                                    </div>
                                    <span class="ttm-zone-pct" ng-style="{'color': getConditionColor(zc)}">
                                        {{ (zc !== undefined ? zc : 0).toFixed(0) }}%
                                    </span>
                                </div>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Dynamic Grip:</span>
                                <span class="ttm-value" ng-style="{'color': getGripColor(w.tyreGrip)}">
                                    {{ ((w.tyreGrip || 0) * 100).toFixed(0) }}%
                                </span>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Tire Pressure:</span>
                                <span class="ttm-value">
                                    <span ng-style="{'color': getInflationColor(w.pressure, w.targetHotPressure || w.optimalPressure)}">
                                        {{ (w.pressure !== undefined ? w.pressure : 0).toFixed(0) }} PSI
                                    </span>
                                    <span style="font-size: 9px; color: #64748b;">
                                        (Hot {{ (w.targetHotPressure || w.optimalPressure || 0).toFixed(0) }})
                                    </span>
                                </span>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Temp State / Opt:</span>
                                <span class="ttm-value">
                                    <span ng-style="{'color': tempCategoryColor(w.tempCategory)}">{{ w.tempCategory || 'Normal' }}</span>
                                    <span style="color:#64748b;"> · avg {{ (w.avgTemp||0).toFixed(0) }}° / opt {{ (w.working_temp||0).toFixed(0) }}°</span>
                                </span>
                            </div>

                            <div class="ttm-section-label">Surface Heat Map (O | M | I):</div>
                            <div class="ttm-thermal-strip">
                                <div class="ttm-thermal-segment"
                                     ng-repeat="tempVal in w.surfaceTemps track by $index"
                                     ng-style="{'background-color': getTempColor(tempVal, w), 'color': '#ffffff'}">
                                    {{ (tempVal !== undefined ? tempVal : 0).toFixed(0) }}°
                                </div>
                            </div>

                            <div class="ttm-section-label">Carcass Heat Map (O | M | I):</div>
                            <div class="ttm-thermal-strip">
                                <div class="ttm-thermal-segment"
                                     ng-repeat="tempVal in w.carcassTemps track by $index"
                                     ng-style="{'background-color': getTempColor(tempVal, w), 'color': '#ffffff'}">
                                    {{ (tempVal !== undefined ? tempVal : 0).toFixed(0) }}°
                                </div>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Rim:</span>
                                <span class="ttm-value" ng-style="{'color': getTempColor(w.rimTemp, w)}">
                                    {{ (w.rimTemp !== undefined ? w.rimTemp : 0).toFixed(0) }}°
                                </span>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Stint Fade:</span>
                                <span class="ttm-value" ng-style="{'color': getDiagnosticColor(w.stintFade)}">
                                    {{ (w.stintFade || 0).toFixed(0) }}%
                                </span>
                            </div>
                            <div class="ttm-bar-container" style="margin-bottom: 5px;">
                                <div class="ttm-bar-fill" ng-style="{'width': (w.stintFade || 0) + '%', 'background-color': getDiagnosticColor(w.stintFade)}"></div>
                            </div>

                            <div class="ttm-diagnostics-grid" ng-if="hasDamage(w)">
                                <div class="ttm-diagnostic-item">
                                    <span class="ttm-diag-label">BLISTER</span>
                                    <span class="ttm-value" ng-style="{'color': getDiagnosticColor(w.blistering)}">{{ (w.blistering || 0).toFixed(0) }}%</span>
                                    <div class="ttm-bar-container">
                                        <div class="ttm-bar-fill" ng-style="{'width': (w.blistering || 0) + '%', 'background-color': '#f43f5e'}"></div>
                                    </div>
                                </div>
                                <div class="ttm-diagnostic-item">
                                    <span class="ttm-diag-label">GRAINING</span>
                                    <span class="ttm-value" ng-style="{'color': getDiagnosticColor(w.graining)}">{{ (w.graining || 0).toFixed(0) }}%</span>
                                    <div class="ttm-bar-container">
                                        <div class="ttm-bar-fill" ng-style="{'width': (w.graining || 0) + '%', 'background-color': getDiagnosticColor(w.graining)}"></div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            `,
            replace: true,
            restrict: "EA",
            link: function (scope, element, attrs) {
                var StreamsManager = window.StreamsManager || ($injector.has("StreamsManager") ? $injector.get("StreamsManager") : null);
                var streamsList = ["TireWearThermals"];

                if (StreamsManager) {
                    StreamsManager.add(streamsList);
                }


                var LERP_K = 12;
                var LERP_EPS = 0.05;
                var DIGEST_INTERVAL_MS = 50;
                var DIAG_HIDE_THRESHOLD = 1.5;
                var rafId = null;
                var lastRafTs = 0;
                var lastDigestTs = 0;
                var rafRunning = false;
                var targetWheels = [];
                var WHEEL_LERP_KEYS = [
                    "condition", "conditionScalar", "conditionNode", "nodeWearPeak",
                    "tyreGrip", "pressure", "avgTemp",
                    "working_temp", "rimTemp", "stintFade",
                    "graining", "blistering"
                ];

                scope.wheels = [];

                // Profiles whose scalar life is provisional / fallback (see tools/SPECTRA_STATUS.md).
                var PROVISIONAL_PROFILES = {
                    truck: true, truck_offroad: true, light_truck_std: true, light_truck_hd: true,
                    vintage: true, allterrain: true, mudterrain: true, crawler: true, paddle: true,
                    highway_utility_utility: true
                };

                scope.formatProfile = function (profile) {
                    if (!profile) return "";
                    var raw = String(profile);
                    var key = raw.toLowerCase().replace(/\s+/g, "_");
                    var pretty = raw.replace(/_/g, " ");
                    if (PROVISIONAL_PROFILES[key] || /utility|truck|vintage|allterrain|mudterrain|crawler|paddle/.test(key)) {
                        return pretty + " · provisional";
                    }
                    return pretty;
                };

                scope.tempCategoryColor = function (cat) {
                    if (cat === "Cold") return "#38bdf8";
                    if (cat === "Hot") return "#ef4444";
                    return "#10b981";
                };

                scope.getConditionColor = function (condition) {
                    if (condition === undefined) return "#10b981";
                    var ratio = condition / 100;
                    if (ratio > 0.7) return "#10b981";
                    if (ratio > 0.4) return "#f59e0b";
                    return "#ef4444";
                };

                scope.zoneFillHeight = function (zc) {
                    var v = (zc === undefined || zc === null) ? 0 : zc;
                    if (v < 0) v = 0;
                    if (v > 100) v = 100;
                    return v + "%";
                };

                scope.getGripColor = function (grip) {
                    if (grip === undefined) return "#f1f5f9";
                    if (grip >= 0.95) return "#10b981";
                    if (grip >= 0.85) return "#a3e635";
                    if (grip >= 0.70) return "#f59e0b";
                    return "#ef4444";
                };

                scope.getDiagnosticColor = function (value) {
                    if (!value || value <= 5) return "#94a3b8";
                    if (value <= 25) return "#a3e635";
                    if (value <= 60) return "#f59e0b";
                    return "#ef4444";
                };

                scope.getInflationColor = function (pressure, optimalPressure) {
                    if (pressure === undefined) return "#f1f5f9";
                    var opt = optimalPressure || 25;
                    if (opt <= 0) opt = 25;
                    var ratio = pressure / opt;
                    if (pressure < 5) return "#ef4444";
                    if (ratio < 0.75) return "#38bdf8";
                    if (ratio < 0.90) return "#a3e635";
                    if (ratio <= 1.25) return "#10b981";
                    if (ratio <= 1.40) return "#f59e0b";
                    return "#ef4444";
                };

                function smoothstep01(t) {
                    t = Math.min(Math.max(t, 0), 1);
                    return t * t * (3 - 2 * t);
                }

                // Color from this wheel's streamed grip window (thermalGripWindow edges).
                scope.getTempColor = function (tempVal, wheel) {
                    var sat = 80;
                    var lit = 45;
                    if (tempVal === undefined || tempVal === null) {
                        return "hsla(240, " + sat + "%, " + lit + "%, 1)";
                    }
                    var opt = wheel && wheel.optimalTemp;
                    var plateau = wheel && wheel.tempPlateau;
                    var coldW = wheel && wheel.coldWidth;
                    var hotW = wheel && wheel.hotWidth;
                    if (!(opt > 0) || plateau === undefined || plateau === null
                        || coldW === undefined || coldW === null
                        || hotW === undefined || hotW === null) {
                        return "hsla(240, " + sat + "%, " + lit + "%, 1)";
                    }
                    var coldEdge = opt - plateau;
                    var hotEdge = opt + plateau;
                    if (tempVal >= coldEdge && tempVal <= hotEdge) {
                        return "hsla(120, " + sat + "%, " + lit + "%, 1)";
                    }
                    if (tempVal < coldEdge) {
                        var tC = smoothstep01(coldW > 0 ? (coldEdge - tempVal) / coldW : 1);
                        var hueC = 200 + tC * 40;
                        var litC = Math.max(22, lit - tC * 8);
                        return "hsla(" + Math.round(hueC) + ", " + sat + "%, " + Math.round(litC) + "%, 1)";
                    }
                    var tH = smoothstep01(hotW > 0 ? (tempVal - hotEdge) / hotW : 1);
                    var hueH = 28 * (1 - tH);
                    var litH = Math.max(22, lit - tH * 22);
                    return "hsla(" + Math.round(hueH) + ", " + sat + "%, " + Math.round(litH) + "%, 1)";
                };

                scope.hasDamage = function (w) {
                    if (!w) return false;
                    return (w.blistering || 0) > DIAG_HIDE_THRESHOLD
                        || (w.graining || 0) > DIAG_HIDE_THRESHOLD;
                };

                function lerpNum(cur, tgt, alpha) {
                    if (tgt === undefined || tgt === null) return cur;
                    if (cur === undefined || cur === null) return tgt;
                    var next = cur + (tgt - cur) * alpha;
                    return Math.abs(tgt - next) < LERP_EPS ? tgt : next;
                }

                function ensureArr3(dst, a, b, c) {
                    if (!dst || dst.length !== 3) return [a || 0, b || 0, c || 0];
                    dst[0] = a || 0;
                    dst[1] = b || 0;
                    dst[2] = c || 0;
                    return dst;
                }

                function prepareWheelTemps(w) {
                    if (!w) return;
                    var t = w.temp || [];
                    w.surfaceTemps = ensureArr3(w.surfaceTemps, t[0], t[1], t[2]);
                    w.carcassTemps = ensureArr3(w.carcassTemps, t[3], t[4], t[5]);
                    if (w.rimTemp === undefined || w.rimTemp === null) w.rimTemp = t[6] || 0;
                    // A3: O|M|I from stream; fall back to overall condition (peak-based when spike on)
                    var c = w.condition !== undefined && w.condition !== null ? w.condition : 100;
                    var zc = w.zoneCondition;
                    if (!zc || zc.length !== 3) {
                        w.zoneCondition = [c, c, c];
                    } else {
                        w.zoneCondition = ensureArr3(
                            w.zoneCondition,
                            zc[0] !== undefined && zc[0] !== null ? zc[0] : c,
                            zc[1] !== undefined && zc[1] !== null ? zc[1] : c,
                            zc[2] !== undefined && zc[2] !== null ? zc[2] : c
                        );
                    }
                }

                function copyStaticWheel(dst, src) {
                    dst.name = src.name;
                    dst.profile = src.profile;
                    dst.tempCategory = src.tempCategory;
                    dst.targetHotPressure = src.targetHotPressure;
                    dst.optimalPressure = src.optimalPressure;
                    dst.optimalTemp = src.optimalTemp;
                    dst.tempPlateau = src.tempPlateau;
                    dst.coldWidth = src.coldWidth;
                    dst.hotWidth = src.hotWidth;
                    dst.gripMultiplier = src.gripMultiplier;
                    dst.thermalGrip = src.thermalGrip;
                }

                function snapLerpArrays(dst, src) {
                    var st = src.surfaceTemps || [0, 0, 0];
                    var ct = src.carcassTemps || [0, 0, 0];
                    var zc = src.zoneCondition || [100, 100, 100];
                    dst.surfaceTemps = [st[0] || 0, st[1] || 0, st[2] || 0];
                    dst.carcassTemps = [ct[0] || 0, ct[1] || 0, ct[2] || 0];
                    dst.zoneCondition = [zc[0] || 0, zc[1] || 0, zc[2] || 0];
                }

                function snapLerpScalars(dst, src) {
                    for (var i = 0; i < WHEEL_LERP_KEYS.length; i++) {
                        var k = WHEEL_LERP_KEYS[i];
                        dst[k] = src[k] !== undefined && src[k] !== null ? src[k] : 0;
                    }
                }

                function makeDisplayWheel(src) {
                    var dst = {};
                    copyStaticWheel(dst, src);
                    snapLerpScalars(dst, src);
                    snapLerpArrays(dst, src);
                    return dst;
                }

                function setTargetWheel(dst, src) {
                    copyStaticWheel(dst, src);
                    snapLerpScalars(dst, src);
                    snapLerpArrays(dst, src);
                }

                function isAppVisible() {
                    if (document.hidden) return false;
                    var el = element[0];
                    if (!el) return false;

                    return !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length);
                }

                function stopRaf() {
                    if (rafId !== null) {
                        cancelAnimationFrame(rafId);
                        rafId = null;
                    }
                    rafRunning = false;
                    lastRafTs = 0;
                }

                function startRaf() {
                    if (rafRunning || !isAppVisible()) return;
                    rafRunning = true;
                    lastRafTs = 0;
                    lastDigestTs = 0;
                    rafId = requestAnimationFrame(rafTick);
                }

                function lerpDisplay(alpha) {
                    var moved = false;
                    var i, j, k, prev, d, t;

                    var n = Math.min(scope.wheels.length, targetWheels.length);
                    for (i = 0; i < n; i++) {
                        d = scope.wheels[i];
                        t = targetWheels[i];
                        copyStaticWheel(d, t);
                        for (j = 0; j < WHEEL_LERP_KEYS.length; j++) {
                            k = WHEEL_LERP_KEYS[j];
                            prev = d[k];
                            d[k] = lerpNum(d[k], t[k], alpha);
                            if (d[k] !== prev) moved = true;
                        }
                        for (j = 0; j < 3; j++) {
                            prev = d.surfaceTemps[j];
                            d.surfaceTemps[j] = lerpNum(d.surfaceTemps[j], t.surfaceTemps[j], alpha);
                            if (d.surfaceTemps[j] !== prev) moved = true;

                            prev = d.carcassTemps[j];
                            d.carcassTemps[j] = lerpNum(d.carcassTemps[j], t.carcassTemps[j], alpha);
                            if (d.carcassTemps[j] !== prev) moved = true;

                            if (!d.zoneCondition || d.zoneCondition.length !== 3) d.zoneCondition = [100, 100, 100];
                            if (!t.zoneCondition || t.zoneCondition.length !== 3) t.zoneCondition = [100, 100, 100];
                            prev = d.zoneCondition[j];
                            d.zoneCondition[j] = lerpNum(d.zoneCondition[j], t.zoneCondition[j], alpha);
                            if (d.zoneCondition[j] !== prev) moved = true;
                        }
                    }
                    return moved;
                }

                function digestDisplay() {
                    if (scope.$$phase) return;
                    scope.$digest();
                }

                function rafTick(ts) {
                    if (!rafRunning) return;
                    if (!isAppVisible()) {
                        stopRaf();
                        return;
                    }
                    var dt = lastRafTs ? Math.min(0.05, (ts - lastRafTs) / 1000) : (1 / 60);
                    lastRafTs = ts;
                    var alpha = Math.min(1, LERP_K * dt);
                    var moved = lerpDisplay(alpha);

                    if (!moved || !lastDigestTs || (ts - lastDigestTs) >= DIGEST_INTERVAL_MS) {
                        lastDigestTs = ts;
                        digestDisplay();
                    }
                    if (moved) {
                        rafId = requestAnimationFrame(rafTick);
                    } else {
                        stopRaf();
                    }
                }

                function onVisibilityChange() {
                    if (!isAppVisible()) {
                        stopRaf();
                    } else if (targetWheels.length) {
                        startRaf();
                    }
                }
                document.addEventListener("visibilitychange", onVisibilityChange);

                var boundVehId = null;
                var boundResetGen = null;
                function resetNtfStreamBind() {
                    boundVehId = null;
                    boundResetGen = null;
                }
                function acceptNtfStream(dataStream) {
                    if (!dataStream || !dataStream.data || dataStream.mpRemote) return false;
                    var id = dataStream.vehId;
                    if (id === undefined || id === null) return true;
                    if (boundVehId === null) {
                        boundVehId = id;
                        if (dataStream.resetGen !== undefined && dataStream.resetGen !== null) {
                            boundResetGen = dataStream.resetGen;
                        }
                        return true;
                    }
                    if (id !== boundVehId) return false;
                    var gen = dataStream.resetGen;
                    if (gen !== undefined && gen !== null && boundResetGen !== null && gen < boundResetGen) {
                        return false;
                    }
                    return true;
                }
                function isNtfLifeReset(dataStream) {
                    var gen = dataStream.resetGen;
                    if (gen === undefined || gen === null) return false;
                    if (boundResetGen === null) {
                        boundResetGen = gen;
                        return false;
                    }
                    if (gen > boundResetGen) {
                        boundResetGen = gen;
                        return true;
                    }
                    return false;
                }

                function ingestStream(dataStream) {
                    if (!acceptNtfStream(dataStream)) return;

                    var src = dataStream.data;
                    var count = src.length;
                    var lifeReset = isNtfLifeReset(dataStream);
                    var structural = lifeReset || (scope.wheels.length !== count);
                    var i, w;

                    for (i = 0; i < count; i++) {
                        prepareWheelTemps(src[i]);
                    }

                    if (structural) {
                        stopRaf();
                        targetWheels = [];
                        var wheels = [];
                        for (i = 0; i < count; i++) {
                            w = src[i] || {};
                            var tgt = {};
                            setTargetWheel(tgt, w);
                            targetWheels.push(tgt);
                            wheels.push(makeDisplayWheel(w));
                        }
                        scope.wheels = wheels;
                        if (!scope.$$phase) {
                            scope.$evalAsync(angular.noop);
                        }
                    } else {
                        for (i = 0; i < count; i++) {
                            setTargetWheel(targetWheels[i], src[i] || {});
                        }
                        startRaf();
                    }
                }

                scope.$on("$destroy", function () {
                    stopRaf();
                    document.removeEventListener("visibilitychange", onVisibilityChange);
                    if (StreamsManager) {
                        StreamsManager.remove(streamsList);
                    }
                });

                scope.$on("VehicleChange", resetNtfStreamBind);
                scope.$on("VehicleFocusChanged", resetNtfStreamBind);
                scope.$on("TireWearThermals", function (event, dataStream) {
                    ingestStream(dataStream);
                });

                scope.$on("streamsUpdate", function (event, streams) {
                    if (streams && streams.TireWearThermals) {
                        ingestStream(streams.TireWearThermals);
                    }
                });
            }
        };
    }]);
