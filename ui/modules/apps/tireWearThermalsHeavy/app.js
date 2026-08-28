angular.module("beamng.apps")
    .directive("tireWearThermalsHeavy", ["$injector", function ($injector) {
        return {
            template: `
                <div class="tth-panel-container">
                    <style>
                        .tth-panel-container {
                            width: 100%;
                            height: 100%;
                            max-height: 100%;
                            min-height: 0;
                            background: #020617;
                            border: 2px solid #475569;
                            border-radius: 6px;
                            box-sizing: border-box;
                            font-family: "Lucida Console", Monaco, monospace;
                            color: #f8fafc;
                            overflow-x: hidden;
                            overflow-y: auto;
                            -webkit-overflow-scrolling: touch;
                            padding: 9px;
                            pointer-events: auto;
                            text-shadow: 0 0 3px #000, 0 1px 2px #000, 0 2px 4px #000;
                        }
                        .tth-header {
                            display: flex;
                            justify-content: space-between;
                            align-items: center;
                            border-bottom: 2px solid rgba(255, 255, 255, 0.08);
                            padding-bottom: 6px;
                            margin-bottom: 9px;
                            gap: 6px;
                            flex-wrap: wrap;
                        }
                        .tth-dev-banner {
                            display: block;
                            width: 100%;
                            text-align: center;
                            font-size: 12px;
                            font-weight: bold;
                            letter-spacing: 0.55px;
                            text-transform: uppercase;
                            color: #fef3c7;
                            background: #78350f;
                            border: 1px solid #f59e0b;
                            border-radius: 4px;
                            padding: 5px 10px;
                            margin-bottom: 8px;
                            box-sizing: border-box;
                        }
                        .tth-dev-subtitle {
                            font-size: 12px;
                            color: #cbd5e1;
                            font-weight: normal;
                            letter-spacing: 0.3px;
                            margin-left: 8px;
                        }
                        .tth-title {
                            font-size: 15px;
                            font-weight: bold;
                            letter-spacing: 1.2px;
                            color: #fbbf24;
                        }
                        .tth-header-meta {
                            font-size: 13px;
                            color: #f1f5f9;
                            letter-spacing: 0.4px;
                        }
                        .tth-grid {
                            display: grid;
                            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
                            gap: 10px;
                        }
                        .tth-card {
                            background: #0f172a;
                            border: 1px solid #64748b;
                            border-radius: 5px;
                            padding: 9px;
                            box-sizing: border-box;
                        }
                        .tth-card-header {
                            display: flex;
                            justify-content: space-between;
                            align-items: center;
                            border-bottom: 1px solid rgba(255, 255, 255, 0.08);
                            padding-bottom: 4px;
                            margin-bottom: 7px;
                        }
                        .tth-wheel-name {
                            font-size: 16px;
                            font-weight: bold;
                            color: #7dd3fc;
                        }
                        .tth-compound-tag {
                            font-size: 13px;
                            background: #0c4a6e;
                            border: 1px solid #38bdf8;
                            color: #e0f2fe;
                            padding: 1px 5px;
                            border-radius: 3px;
                            text-transform: uppercase;
                            letter-spacing: 0.4px;
                        }
                        .tth-stat-row {
                            display: flex;
                            justify-content: space-between;
                            margin-bottom: 4px;
                            font-size: 14px;
                        }
                        .tth-label {
                            color: #e2e8f0;
                        }
                        .tth-value {
                            font-weight: bold;
                            color: #ffffff;
                        }
                        .tth-capture-line {
                            display: block;
                            width: 100%;
                            box-sizing: border-box;
                            margin: 4px 0 6px 0;
                            padding: 5px 7px;
                            background: #000000;
                            border: 1px solid #fbbf24;
                            border-radius: 3px;
                            font-size: 15px;
                            font-weight: bold;
                            color: #fef08a;
                            letter-spacing: 0.35px;
                            text-shadow: none;
                            line-height: 1.35;
                        }
                        .tth-capture-line .tth-cap-dim {
                            color: #cbd5e1;
                            font-weight: normal;
                        }
                        .tth-section-label {
                            font-size: 13px;
                            color: #fbbf24;
                            margin-top: 7px;
                            letter-spacing: 0.4px;
                        }
                        .tth-section-label-muted {
                            font-size: 11px;
                            color: #e2e8f0;
                            margin-top: 3px;
                            margin-bottom: 0;
                            letter-spacing: 0.2px;
                        }
                        .tth-thermal-strip {
                            display: grid;
                            grid-template-columns: repeat(3, 1fr);
                            gap: 2px;
                            margin: 1px 0 3px 0;
                            height: 18px;
                        }
                        .tth-thermal-segment {
                            display: flex;
                            align-items: center;
                            justify-content: center;
                            font-size: 11px;
                            font-weight: bold;
                            border-radius: 2px;
                            border: 1px solid #000;
                            color: #ffffff !important;
                            text-shadow: 0 0 2px #000, 0 1px 2px #000, 1px 0 0 #000, -1px 0 0 #000;
                        }
                        .tth-diag-nums {
                            margin-top: 5px;
                            padding-top: 5px;
                            border-top: 1px solid #334155;
                            font-size: 13px;
                            color: #f1f5f9;
                            line-height: 1.35;
                            white-space: normal;
                        }
                        .tth-diag-nums .tth-diag-k {
                            color: #cbd5e1;
                        }
                        .tth-diag-nums .tth-diag-sep {
                            color: #94a3b8;
                            margin: 0 4px;
                        }
                        .tth-bar-container {
                            width: 100%;
                            background: #1e293b;
                            border: 1px solid #334155;
                            border-radius: 3px;
                            height: 5px;
                            overflow: hidden;
                            margin-top: 2px;
                        }
                        .tth-bar-fill {
                            height: 100%;
                        }
                        .tth-wear-map-row {
                            display: flex;
                            align-items: center;
                            gap: 10px;
                            margin: 4px 0 2px 0;
                            padding: 4px;
                            background: #000000;
                            border: 1px solid #475569;
                            border-radius: 4px;
                        }
                        .tth-wear-ring {
                            position: relative;
                            width: 60px;
                            height: 60px;
                            flex-shrink: 0;
                            border-radius: 50%;
                            background: #1e293b;
                            box-shadow: inset 0 0 0 2px #cbd5e1;
                        }
                        .tth-wear-ring-hole {
                            position: absolute;
                            left: 50%;
                            top: 50%;
                            width: 22px;
                            height: 22px;
                            margin: -11px 0 0 -11px;
                            border-radius: 50%;
                            background: #020617;
                            box-shadow: inset 0 0 0 1px #64748b;
                            z-index: 2;
                        }
                        .tth-wear-contact-tick {
                            position: absolute;
                            left: 50%;
                            top: 1px;
                            width: 0;
                            height: 0;
                            margin-left: -5px;
                            border-left: 5px solid transparent;
                            border-right: 5px solid transparent;
                            border-bottom: 9px solid #fef08a;
                            transform-origin: 5px 29px;
                            z-index: 3;
                            pointer-events: none;
                            filter: drop-shadow(0 0 2px #000);
                        }
                        .tth-wear-map-meta {
                            flex: 1;
                            min-width: 0;
                            font-size: 13px;
                            color: #f1f5f9;
                            line-height: 1.35;
                            text-shadow: none;
                        }
                        .tth-wear-map-meta strong {
                            color: #fef08a;
                        }
                        /* Capture-focused test channels (Patch/Heat, drive gates, slip) */
                        .tth-test-channels .tth-stat-row {
                            font-size: 15px;
                            margin-bottom: 5px;
                        }
                        .tth-test-channels .tth-section-label {
                            font-size: 14px;
                            margin-top: 9px;
                        }
                        /* Symmetrical Diagnostics Dashboard */
                        .tth-diagnostics-grid {
                            display: grid;
                            grid-template-columns: 1fr 1fr;
                            gap: 7px;
                            border-top: 1px dashed rgba(255, 255, 255, 0.08);
                            margin-top: 7px;
                            padding-top: 7px;
                        }
                        .tth-diagnostic-item {
                            font-size: 13px;
                        }
                        .tth-diag-label {
                            color: #e2e8f0;
                            display: block;
                            margin-bottom: 2px;
                            font-size: 14px;
                            letter-spacing: 0.4px;
                        }
                        .tth-footer {
                            font-size: 14px;
                            color: #e2e8f0;
                            text-align: right;
                            margin-top: 6px;
                        }
                    </style>

                    <div class="tth-dev-banner">DEV / TESTING — not for public release</div>
                    <div class="tth-header">
                        <span class="tth-title">NODE-THERMAL FRICTION<span class="tth-dev-subtitle">Pitwall · capture-first · node spike</span></span>
                        <span class="tth-header-meta">
                            Env {{ (envTemp||0).toFixed(2) }}°C · Track {{ (trackTemp||0).toFixed(2) }}°C · Rain {{ (rainState||0).toFixed(2) }}% · Film {{ (waterFilm||0).toFixed(2) }}%
                        </span>
                        <span class="tth-header-meta">
                            <span style="color: #e2e8f0;">Aero ↓</span>
                            <span ng-if="aeroNative" style="color: #cbd5e1; font-size: 12px;">native</span>
                            <span style="color: #f59e0b; font-weight: bold;">{{ totalDownforceKN }} kN</span>
                            <span style="color: #e2e8f0; font-size: 14px;">({{ fmtAeroFracPct(aeroFracPct) }}% of load)</span>
                            <span style="color: #e2e8f0; font-size: 14px;">
                                · Drag {{ aeroDragKN }} kN · F/R {{ (aeroFrontPct||0).toFixed(0) }}/{{ (aeroRearPct||0).toFixed(0) }} · CoP {{ (aeroCopPct||0).toFixed(0) }}%
                            </span>
                        </span>
                        <span class="tth-header-meta" style="width: 100%; color: #f1f5f9;">
                            Elev {{ (elevationM||0).toFixed(2) }}m · ToD {{ timeOfDay }} · Cloud {{ (cloudCover||0).toFixed(2) }}% · Wake {{ (packWake||0).toFixed(2) }}% · Δair {{ fmtSigned(packAirDelta, 2) }}°
                            · Stream {{ (streamHz||0).toFixed(0) }} Hz · EnvΔ {{ (envTempRange||0).toFixed(2) }}°
                            · Stint {{ (stintKm||0).toFixed(2) }} km · Odo {{ (odoKm||0).toFixed(2) }} km
                        </span>
                        <span class="tth-header-meta" style="width: 100%; color: #f1f5f9;">
                            Airspeed {{ (airspeedMph||0).toFixed(1) }} mph
                            <span style="color: #cbd5e1; font-size: 12px;">({{ (airspeedMps||0).toFixed(2) }} m/s)</span>
                            · Weight F/R {{ (weightFrontPct||0).toFixed(1) }}/{{ (weightRearPct||0).toFixed(1) }}%
                            · L/R {{ (weightLeftPct||0).toFixed(1) }}/{{ (weightRightPct||0).toFixed(1) }}%
                            · G long/lat {{ fmtSigned(gLong, 2) }}/{{ fmtSigned(gLat, 2) }}
                            <span style="color: #cbd5e1; font-size: 12px;">(|G| {{ (gMag||0).toFixed(2) }})</span>
                            · Yaw {{ fmtSigned(yawRateDeg, 1) }} °/s
                        </span>
                    </div>

                    <div class="tth-grid">
                        <div class="tth-card" ng-repeat="w in wheels">
                            <!-- Wheel Header -->
                            <div class="tth-card-header">
                                <span class="tth-wheel-name">{{ w.name }}</span>
                                <span style="display: flex; gap: 4px; align-items: center; flex-wrap: wrap; justify-content: flex-end;">
                                    <span class="tth-compound-tag">{{ formatProfile(w.compoundClass || w.profile) }}</span>
                                    <span class="tth-compound-tag" ng-if="w.purpose">{{ formatPurpose(w.purpose) }}</span>
                                </span>
                            </div>
                            <div class="tth-stat-row" ng-if="w.profile1 || w.profile2" style="font-size: 14px; margin-top: -3px;">
                                <span class="tth-label">Profiles</span>
                                <span class="tth-value" style="font-size: 14px; color: #e2e8f0;">
                                    {{ formatProfile(w.profile1) }} → {{ formatProfile(w.profile2) }}
                                </span>
                            </div>
                            <div class="tth-stat-row" ng-if="w.classifyReason" style="font-size: 14px; margin-top: -2px;">
                                <span class="tth-label">Classify</span>
                                <span class="tth-value" style="font-size: 14px; color: #e2e8f0;">{{ w.classifyReason }}</span>
                            </div>
                            <div class="tth-stat-row" ng-if="w.dutyMods" style="font-size: 14px; margin-top: -2px;">
                                <span class="tth-label">Duty mods</span>
                                <span class="tth-value" style="font-size: 14px; color: #e2e8f0;">{{ formatDutyMods(w.dutyMods) }}</span>
                            </div>
                            <div class="tth-stat-row" style="font-size: 14px; margin-top: -2px;">
                                <span class="tth-label">Heat knobs</span>
                                <span class="tth-value" style="font-size: 13px; color: #fbbf24;">
                                    air{{ (w.airCoolRate||0).toFixed(3) }}
                                    · vel×{{ (w.skinVelCoolScale!==undefined ? w.skinVelCoolScale : 1).toFixed(2) }}
                                    · g0{{ (w.workHeatG0!==undefined ? w.workHeatG0 : 0.22).toFixed(2) }}
                                    · slip{{ (w.slipHeatRate||0).toFixed(1) }}/work{{ (w.workHeatRate||0).toFixed(1) }}
                                    · trk{{ (w.trackCondMult!==undefined ? w.trackCondMult : 1).toFixed(2) }}
                                </span>
                            </div>

                            <!-- Structural Condition: A1 display hybrid = min(soft scalar, node peak) -->
                            <div class="tth-stat-row">
                                <span class="tth-label">Tread Condition:</span>
                                <span class="tth-value" ng-style="{'color': getConditionColor(w.condition)}">
                                    {{ (w.condition !== undefined ? w.condition : 0).toFixed(1) }}%
                                    <span class="tth-cap-dim">
                                         · sc{{ (w.conditionScalar !== undefined ? w.conditionScalar : w.condition || 0).toFixed(0) }}
                                         · nd{{ (w.conditionNode !== undefined ? w.conditionNode : (100 - (w.nodeWearPeak||0)*100)).toFixed(0) }}
                                         · {{ a1NodeLeadLabel(w) }}
                                    </span>
                                </span>
                            </div>
                            <div class="tth-bar-container" style="margin-bottom: 7px;">
                                <div class="tth-bar-fill" ng-style="{'width': (w.condition || 0) + '%', 'background-color': getConditionColor(w.condition)}"></div>
                            </div>

                            <!-- Friction Grip Utilization -->
                            <div class="tth-stat-row">
                                <span class="tth-label">Dynamic Grip:</span>
                                <span class="tth-value" ng-style="{'color': getGripColor(w.tyreGrip)}">
                                    {{ ((w.tyreGrip || 0) * 100).toFixed(2) }}%
                                </span>
                            </div>

                            <!-- Pressure setup: cold set vs live vs target hot -->
                            <div class="tth-stat-row">
                                <span class="tth-label">Tire Pressure:</span>
                                <span class="tth-value">
                                    <span ng-style="{'color': getInflationColor(w.pressure, w.targetHotPressure || w.optimalPressure)}">
                                        {{ (w.pressure !== undefined ? w.pressure : 0).toFixed(2) }} PSI 
                                    </span>
                                    <span class="tth-compound-tag" style="margin-left: 4px;"
                                          ng-style="{'color': getInflationColor(w.pressure, w.targetHotPressure || w.optimalPressure)}">
                                        {{ pressureBandLabel(w) }}
                                    </span>
                                    <span class="tth-compound-tag" style="margin-left: 4px;"
                                          ng-if="coldSetWarnChip(w)"
                                          ng-style="coldSetWarnStyle(w)">
                                        {{ coldSetWarnChip(w) }}
                                    </span>
                                    <span style="font-size: 14px; color: #e2e8f0;">
                                        (Cold: {{ (w.coldPressure || w.initialPressure || 0).toFixed(2) }} / Hot tgt: {{ (w.targetHotPressure || w.optimalPressure || 0).toFixed(2) }}
                                        · r{{ (w.pressureRatio || 0).toFixed(2) }}
                                        · Lua {{ (w.luaPressure !== undefined ? w.luaPressure : w.pressure || 0).toFixed(1) }}
                                        → Nat {{ (w.nativePressure !== undefined ? w.nativePressure : w.pressure || 0).toFixed(1) }}
                                        <span ng-style="{'color': pressureConvColor(w)}"> Δ{{ pressureDeltaAbs(w) }}</span>)
                                    </span>
                                </span>
                            </div>

                            <!-- Zone wear O|M|I -->
                            <div class="tth-stat-row" style="margin-top: 4px;" ng-if="w.zoneCondition">
                                <span class="tth-label">Zone Wear O|M|I:</span>
                                <span class="tth-value" style="font-size: 13px;">
                                    {{ (w.zoneCondition[0]||0).toFixed(0) }}% |
                                    {{ (w.zoneCondition[1]||0).toFixed(0) }}% |
                                    {{ (w.zoneCondition[2]||0).toFixed(0) }}%
                                </span>
                            </div>

                            <!-- Alignment Parameters -->
                            <div class="tth-stat-row">
                                <span class="tth-label">Camber / Toe:</span>
                                <span class="tth-value" ng-style="{'color': isExcessiveCamber(w.camber) ? '#ffaa44' : '#f1f5f9'}">
                                    {{ fmtSigned(w.camber, 2) }}° /
                                    {{ fmtSigned(w.toe, 2) }}°
                                </span>
                            </div>

                            <div class="tth-stat-row">
                                <span class="tth-label">Temp State / Opt:</span>
                                <span class="tth-value">
                                    <span ng-style="{'color': tempCategoryColor(w.tempCategory)}">{{ w.tempCategory || 'Normal' }}</span>
                                    <span style="color:#e2e8f0;"> · avg {{ (w.avgTemp||0).toFixed(2) }}° / opt {{ (w.working_temp||0).toFixed(2) }}°</span>
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Stint max:</span>
                                <span class="tth-value" ng-style="{'color': getTempColor(w.stintMaxAvgTemp, w.working_temp)}">
                                    {{ (w.stintMaxAvgTemp||0).toFixed(1) }}°
                                    <span style="color:#cbd5e1; font-size: 13px;" ng-if="(w.stintMaxAvgTemp||0) > (w.working_temp||0) * 1.20"> · Hot flash</span>
                                </span>
                            </div>

                            <!-- SURFACE CONTACT + TEST CHANNELS (capture-sized fonts) -->
                            <div class="tth-test-channels">
                            <div class="tth-section-label">SURFACE CONTACT</div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Material / Class:</span>
                                <span class="tth-value" style="font-size: 14px;">
                                    {{ w.surfaceName || '—' }} · {{ formatProfile(w.surfaceType) }}
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">μ static / slide:</span>
                                <span class="tth-value">{{ (w.muStatic||0).toFixed(2) }} / {{ (w.muSlide||0).toFixed(2) }}</span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Depth / Rough / Flags:</span>
                                <span class="tth-value" style="font-size: 14px;">
                                    {{ (w.contactDepth||0).toFixed(2) }}m · r{{ (w.rough||0).toFixed(2) }}
                                    <span ng-if="w.airborne" style="color:#38bdf8;"> · AIR</span>
                                    <span ng-if="w.underWater" style="color:#38bdf8;"> · H2O</span>
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Patch / Heat / DepthBoost:</span>
                                <span class="tth-value" style="font-size: 14px;">
                                    {{ (w.patchFrac||0).toFixed(3) }} × {{ (w.patchHeatScale||1).toFixed(2) }}
                                    · boost{{ (w.depthHeatBoost||1).toFixed(2) }}
                                    <span style="color:#e2e8f0;">
                                        · Hz{{ (w.hertzArea||0).toFixed(4) }} / defl{{ (w.deflArea||0).toFixed(4) }}
                                        · blend{{ (w.depthBlend||0).toFixed(2) }}
                                    </span>
                                </span>
                            </div>
                            <div class="tth-stat-row" ng-if="(w.dualContactBlend||0) > 0">
                                <span class="tth-label">Dual-contact blend:</span>
                                <span class="tth-value">
                                    <span class="tth-compound-tag" style="color:#f59e0b; border-color:rgba(245,158,11,0.35); background:rgba(245,158,11,0.12);">
                                        DUAL {{ (w.dualContactBlend||0).toFixed(2) }}
                                    </span>
                                </span>
                            </div>
                            </div>

                            <!-- Skin / carcass O|M|I (compact) -->
                            <div class="tth-section-label-muted">Surf O|M|I</div>
                            <div class="tth-thermal-strip">
                                <div class="tth-thermal-segment" 
                                     ng-repeat="tempVal in w.surfaceTemps track by $index"
                                     ng-style="{'background-color': getTempColor(tempVal, w.working_temp), 'color': '#ffffff'}">
                                    {{ (tempVal !== undefined ? tempVal : 0).toFixed(2) }}°
                                </div>
                            </div>
                            <div class="tth-section-label-muted">Carc O|M|I</div>
                            <div class="tth-thermal-strip">
                                <div class="tth-thermal-segment" 
                                     ng-repeat="tempVal in w.carcassTemps track by $index"
                                     ng-style="{'background-color': getTempColor(tempVal, w.working_temp), 'color': '#ffffff'}">
                                    {{ (tempVal !== undefined ? tempVal : 0).toFixed(2) }}°
                                </div>
                            </div>

                            <div class="tth-stat-row">
                                <span class="tth-label">Rim / Brake Soak:</span>
                                <span class="tth-value" ng-style="{'color': getTempColor(w.rimTemp, w.working_temp)}">
                                    {{ (w.rimTemp !== undefined ? w.rimTemp : 0).toFixed(2) }} °C
                                </span>
                            </div>

                            <div class="tth-stat-row">
                                <span class="tth-label">Stock Brake (Surf / Core):</span>
                                <span class="tth-value" ng-style="{'color': getTempColor(w.brakeSurface, 400)}">
                                    {{ (w.brakeSurface !== undefined ? w.brakeSurface : 0).toFixed(2) }} /
                                    {{ (w.brakeCore !== undefined ? w.brakeCore : 0).toFixed(2) }} °C
                                    <span style="font-size: 14px; color: #e2e8f0;">
                                        · η{{ ((w.brakeThermalEfficiency !== undefined ? w.brakeThermalEfficiency : 1) * 100).toFixed(0) }}%
                                    </span>
                                </span>
                            </div>

                            <div class="tth-stat-row">
                                <span class="tth-label">Brake→rim soak:</span>
                                <span class="tth-value" style="font-size: 13px;">
                                    {{ fmtSigned(w.brakeSoakRateCs, 2) }} °C/s
                                    · duct air×{{ (w.ductAirCoolFactor !== undefined ? w.ductAirCoolFactor : 1).toFixed(2) }}
                                    / soak×{{ (w.ductSoakCondFactor !== undefined ? w.ductSoakCondFactor : 1.15).toFixed(2) }}
                                </span>
                            </div>

                            <div class="tth-stat-row">
                                <span class="tth-label">Internal Air Cavity:</span>
                                <span class="tth-value" ng-style="{'color': getTempColor(w.airTemp, w.working_temp)}">
                                    {{ (w.airTemp !== undefined ? w.airTemp : 0).toFixed(2) }} °C
                                </span>
                            </div>

                            <div class="tth-stat-row">
                                <span class="tth-label">Skin−carcass gap:</span>
                                <span class="tth-value" ng-style="{'color': isLargeSkinGap(w.skinCarcassGap) ? '#f59e0b' : '#f1f5f9'}">
                                    {{ fmtSigned(w.skinCarcassGap, 2) }} °C
                                </span>
                            </div>

                            <!-- TEST / PHYSICS CHANNELS -->
                            <div class="tth-test-channels">
                            <div class="tth-section-label">TEST CHANNELS</div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Drive heat gate S/C:</span>
                                <span class="tth-value">
                                    {{ ((w.driveHeatGate||0)*100).toFixed(2) }}% /
                                    {{ ((w.driveHeatGateCarcass||0)*100).toFixed(2) }}%
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Street slip scale / util nudge:</span>
                                <span class="tth-value" style="font-size: 14px;">
                                    ×{{ (w.streetSlipScale !== undefined ? w.streetSlipScale : 1).toFixed(2) }}
                                    · util{{ (w.utilNudge !== undefined ? w.utilNudge : 1).toFixed(2) }}
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Wheel speed:</span>
                                <span class="tth-value">
                                    {{ (w.wheelSpeedMph || 0).toFixed(1) }} mph
                                    <span style="font-size: 14px; color: #e2e8f0;">({{ (w.wheelSpeedMps || 0).toFixed(2) }} m/s)</span>
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Load / Peak F:</span>
                                <span class="tth-value">
                                    {{ (w.loadN || 0).toFixed(0) }} N
                                    <span style="font-size: 14px; color: #e2e8f0;">({{ (w.loadPct || 0).toFixed(1) }}%)</span>
                                    / {{ (w.peakForce || 0).toFixed(0) }} N
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Aero Downforce:</span>
                                <span class="tth-value" style="color: #f59e0b;">
                                    {{ (w.aeroLoadN || 0) >= 1000 || (w.aeroLoadN || 0) <= -1000
                                        ? (fmtSigned((w.aeroLoadN || 0) / 1000, 2) + ' kN')
                                        : (fmtSigned(w.aeroLoadN, 2) + ' N') }}
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Grip long / lat:</span>
                                <span class="tth-value">{{ ((w.longGrip||0)*100).toFixed(2) }}% / {{ ((w.latGrip||0)*100).toFixed(2) }}%</span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Lock fade (off):</span>
                                <span class="tth-value" ng-style="{'color': (w.lockFade||0) > 0.4 ? '#f59e0b' : '#f1f5f9'}">
                                    {{ ((w.lockFade||0)*100).toFixed(0) }}%
                                </span>
                            </div>
                            <div class="tth-section-label">NODE SPIKE</div>
                            <div class="tth-cap-dim" style="margin: 0 0 4px 0; font-size: 10px;">
                                A1: Cond = min(scalar,node) · grip = node μ (no wearPenalty)
                            </div>
                            <div class="tth-capture-line">
                                {{ w.name }} · {{ (w.nodeSpikeOn === 1 || w.nodeSpikeOn === true) ? 'ON' : 'OFF' }} {{ w.nodeGate || 'idle' }}
                                · Cond{{ (w.condition !== undefined ? w.condition : 100).toFixed(0) }}
                                · c{{ ((w.nodeWearContact||0)*100).toFixed(0) }}%
                                · peak{{ ((w.nodeWearPeak||0)*100).toFixed(0) }}%
                                · n{{ (w.nodeWearTouched||0) }}
                                · L:{{ w.nodeLockEnergySrc || 'idle' }}/C:{{ w.nodeCamEnergySrc || 'idle' }}
                                <span class="tth-cap-dim" ng-if="(w.nodeCamFrac||0) > 0"> · camF{{ (w.nodeCamFrac||0).toFixed(2) }}</span>
                                <span class="tth-cap-dim" ng-if="absHint(w)"> · {{ absHint(w) }}</span>
                                <span class="tth-cap-dim"> · fade{{ ((w.lockFade||0)*100).toFixed(0) }}%</span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Spike / gate:</span>
                                <span class="tth-value" ng-style="{'color': (w.nodeGate==='lock' || w.nodeGate==='lock+cam' || w.nodeGate==='drift' || w.nodeGate==='drift+cam') ? '#f59e0b' : '#f1f5f9'}">
                                    {{ (w.nodeSpikeOn === 1 || w.nodeSpikeOn === true) ? 'ON' : 'OFF' }} · {{ w.nodeGate || 'idle' }}
                                    <span class="tth-cap-dim" ng-if="absHint(w)"> · {{ absHint(w) }}</span>
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">A1 Cond sc|nd:</span>
                                <span class="tth-value" style="font-size: 14px;">
                                    {{ (w.condition !== undefined ? w.condition : 100).toFixed(0) }}%
                                    <span class="tth-cap-dim"> hybrid</span>
                                    · sc{{ (w.conditionScalar !== undefined ? w.conditionScalar : w.condition || 100).toFixed(0) }}
                                    · nd{{ (w.conditionNode !== undefined ? w.conditionNode : (100 - (w.nodeWearPeak||0)*100)).toFixed(0) }}
                                    <span class="tth-cap-dim"> · {{ a1NodeLeadLabel(w) }}</span>
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Camber frac:</span>
                                <span class="tth-value" style="font-size: 14px;">
                                    {{ (w.nodeCamFrac||0).toFixed(2) }}
                                    <span class="tth-cap-dim" ng-if="(w.nodeCamFrac||0) <= 0"> · off/&lt;{{ (w.nodeCamArmDeg||1).toFixed(1) }}°</span>
                                    <span class="tth-cap-dim" ng-if="(w.nodeCamFrac||0) > 0 && (w.nodeCamFrac||0) < 0.30"> · street/soft</span>
                                    <span class="tth-cap-dim" ng-if="(w.nodeCamFrac||0) >= 0.30 && (w.nodeCamFrac||0) < 0.55"> · sport</span>
                                    <span class="tth-cap-dim" ng-if="(w.nodeCamFrac||0) >= 0.55 && (w.nodeCamFrac||0) < 0.85"> · aggressive</span>
                                    <span class="tth-cap-dim" ng-if="(w.nodeCamFrac||0) >= 0.85"> · race</span>
                                    <span class="tth-cap-dim" ng-if="(w.nodeCamColScale||1) < 0.99"> · col×{{ (w.nodeCamColScale||1).toFixed(2) }}</span>
                                    <span class="tth-cap-dim" ng-if="(w.nodeCamArmDeg||1) > 1.05"> · arm{{ (w.nodeCamArmDeg||1).toFixed(1) }}°</span>
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Contact cid / ω:</span>
                                <span class="tth-value" style="font-size: 14px;">
                                    {{ (w.nodeContactCid||0) }} · {{ (w.nodeOmega||0).toFixed(1) }} rad/s
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Wear c/peak / n:</span>
                                <span class="tth-value" ng-style="{'color': (w.nodeWearPeak||0) > 0.15 ? '#f59e0b' : '#f1f5f9'}">
                                    {{ ((w.nodeWearContact||0)*100).toFixed(0) }}% /
                                    {{ ((w.nodeWearPeak||0)*100).toFixed(0) }}% ·
                                    n{{ (w.nodeWearTouched||0) }}
                                </span>
                            </div>
                            <div class="tth-wear-map-row" ng-if="(w.nodeWearRingN||0) > 0 || (w.nodeWearPeak||0) > 0.005">
                                <div class="tth-wear-ring" ng-style="{'background': wearRingGradient(w)}">
                                    <div class="tth-wear-ring-hole"></div>
                                    <div class="tth-wear-contact-tick"
                                         ng-if="(w.nodeWearRingContact||0) > 0"
                                         ng-style="{'transform': 'rotate(' + (((w.nodeWearRingContact||1) - 0.5) * 360 / (w.nodeWearRingN||1)) + 'deg)'}"></div>
                                </div>
                                <div class="tth-wear-map-meta">
                                    <div><strong>Wear map</strong> · {{ w.nodeWearRingN || 0 }} rays</div>
                                    <div>contact ray {{ (w.nodeWearRingContact||0) || '—' }} · max {{ ((w.nodeWearPeak||0)*100).toFixed(0) }}%</div>
                                    <div style="color:#cbd5e1;">CW when rolling · sector = bright arc</div>
                                </div>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">μ F/S · mass:</span>
                                <span class="tth-value" style="font-size: 14px;">
                                    ×{{ (w.nodeMuScale !== undefined ? w.nodeMuScale : 1).toFixed(2) }} /
                                    {{ (w.nodeSlideScale !== undefined ? w.nodeSlideScale : 1).toFixed(2) }}
                                    · m{{ (w.nodeMassScale !== undefined ? w.nodeMassScale : 1).toFixed(2) }}
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Slip E / long / side:</span>
                                <span class="tth-value" style="font-size: 14px;">
                                    {{ (w.slipEnergy||0).toFixed(2) }} / {{ fmtSigned(w.longSlip, 2) }} / {{ fmtSigned(w.sideSlip, 2) }}
                                </span>
                            </div>
                            <div class="tth-section-label" ng-if="w.nodeColOn">COL ENERGY (probe)</div>
                            <div class="tth-capture-line" ng-if="w.nodeColOn"
                                 ng-style="{'color': (w.nodeColHoldSlipHits||0) > 0 ? '#fde047' : '#cbd5e1'}">
                                {{ w.name }} · map{{ (w.nodeColMapN||0) }}
                                · holdHits{{ (w.nodeColHoldHits||0) }}/s{{ (w.nodeColHoldSlipHits||0) }}
                                · slipF{{ (w.nodeColHoldSlipF||0).toFixed(0) }}
                                · colE{{ (w.nodeColHoldEnergy||0).toFixed(0) }}
                                · win{{ (w.nodeColHoldWin||0).toFixed(0) }}
                                · cid{{ (w.nodeColPeakCid||0) }}/{{ (w.nodeColWheelCid||0) }}
                                · {{ (w.nodeColMatch===1) ? 'Y' : 'N' }}
                            </div>
                            <div class="tth-stat-row" ng-if="w.nodeColOn">
                                <span class="tth-label">Live hits / slip:</span>
                                <span class="tth-value" style="font-size: 14px;">
                                    {{ (w.nodeColHits||0) }} / {{ (w.nodeColSlipHits||0) }}
                                    · slipF {{ (w.nodeColSlipF||0).toFixed(1) }}
                                </span>
                            </div>
                            <div class="tth-stat-row" ng-if="w.nodeColOn">
                                <span class="tth-label">Hold slipF / slipV:</span>
                                <span class="tth-value" ng-style="{'color': (w.nodeColHoldSlipF||0) > 50 ? '#f59e0b' : '#f1f5f9'}" style="font-size: 14px;">
                                    {{ (w.nodeColHoldSlipF||0).toFixed(1) }} N · {{ (w.nodeColHoldSlipV||0).toFixed(3) }} m/s
                                </span>
                            </div>
                            <div class="tth-stat-row" ng-if="w.nodeColOn">
                                <span class="tth-label">Hold colE Σ / win · slipE:</span>
                                <span class="tth-value" style="font-size: 14px;">
                                    {{ (w.nodeColHoldEnergy||0).toFixed(1) }} / {{ (w.nodeColHoldWin||0).toFixed(1) }}
                                    · {{ (w.slipEnergy||0).toFixed(2) }}
                                </span>
                            </div>
                            <div class="tth-stat-row" ng-if="w.nodeColOn">
                                <span class="tth-label">Peak cid / wheel cid:</span>
                                <span class="tth-value" ng-style="{'color': (w.nodeColMatch===1) ? '#10b981' : '#f59e0b'}" style="font-size: 14px;">
                                    {{ (w.nodeColPeakCid||0) }} / {{ (w.nodeColWheelCid||0) }}
                                    · match {{ (w.nodeColMatch===1) ? 'Y' : 'N' }}
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Susp z / vel / stress:</span>
                                <span class="tth-value" style="font-size: 14px;">
                                    {{ fmtSigned(w.suspCompressionMm, 2) }}mm · {{ fmtSigned(w.suspVel, 2) }}m/s · {{ fmtSigned(w.suspStress, 2) }}
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Bump / Droop / Rdyn:</span>
                                <span class="tth-value" style="font-size: 14px;">
                                    {{ fmtSigned(w.suspBumpMm, 2) }} / {{ fmtSigned(w.suspDroopMm, 2) }} mm · {{ (w.dynamicRadius||0).toFixed(2) }}m
                                </span>
                            </div>
                            </div>

                            <!-- Damage modes: one compact number row -->
                            <div class="tth-diag-nums">
                                <span class="tth-diag-k">Clog</span>
                                <span class="tth-value" ng-style="{'color': getDiagnosticColor(w.clog)}">{{ (w.clog || 0).toFixed(0) }}%</span>
                                <span class="tth-diag-sep">·</span>
                                <span class="tth-diag-k">Grain</span>
                                <span class="tth-value" ng-style="{'color': getDiagnosticColor(w.graining)}">{{ (w.graining || 0).toFixed(0) }}%</span>
                                <span class="tth-diag-sep">·</span>
                                <span class="tth-diag-k">Blister</span>
                                <span class="tth-value" ng-style="{'color': getDiagnosticColor(w.blistering)}">{{ (w.blistering || 0).toFixed(0) }}%</span>
                                <span class="tth-diag-sep">·</span>
                                <span class="tth-diag-k">Leak/Film</span>
                                <span class="tth-value">{{ (w.leak || 0).toFixed(0) }}%/{{ (w.waterFilm || 0).toFixed(0) }}%</span>
                            </div>

                            <div class="tth-footer">
                                Heat Cycles: <span style="color: #f1f5f9; font-weight: bold;">{{ (w.cycles || 0).toFixed(0) }}</span>
                                &nbsp;|&nbsp; Stint Fade: <span style="color: #f1f5f9; font-weight: bold;">{{ (w.stintFade || 0).toFixed(0) }}%</span>
                                &nbsp;|&nbsp; Duct: <span style="color: #f1f5f9; font-weight: bold;">{{ (w.ductPercent || 1).toFixed(0) }}%</span>
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
                } else {
                    console.warn("tireWearThermalsHeavy: StreamsManager service was not found in this injector context.");
                }

                // Client-side smooth motion: Lua ~30 Hz; RAF lerps display toward targets.
                // Digest is throttled (~20 Hz): full $digest every RAF stalls CEF under Heavy binding load.
                var LERP_K = 12;
                var LERP_EPS = 0.05;
                var DIGEST_INTERVAL_MS = 50; // ~20 Hz Angular updates; RAF still lerps at display rate
                var rafId = null;
                var lastRafTs = 0;
                var lastDigestTs = 0;
                var rafRunning = false;
                var targetWheels = [];
                var targetMeta = {
                    envTemp: 21,
                    trackTemp: 21,
                    rainState: 0,
                    waterFilm: 0,
                    totalDownforceN: 0,
                    aeroFracPct: 0,
                    aeroDragN: 0,
                    aeroFrontPct: 0,
                    aeroRearPct: 0,
                    aeroCopPct: 0,
                    elevationM: 0,
                    timeOfDay: 0,
                    cloudCover: 0,
                    packWake: 0,
                    packAirDelta: 0,
                    envTempRange: 0,
                    stintKm: 0,
                    odoKm: 0,
                    airspeedMps: 0,
                    airspeedMph: 0,
                    weightFrontPct: 0,
                    weightRearPct: 0,
                    weightLeftPct: 0,
                    weightRightPct: 0,
                    gLong: 0,
                    gLat: 0,
                    gMag: 0,
                    yawRateDeg: 0
                };
                var WHEEL_LERP_KEYS = [
                    "condition", "tyreGrip", "pressure", "pressureRatio", "camber", "toe", "avgTemp",
                    "working_temp", "rimTemp", "airTemp", "aeroLoadN", "skinCarcassGap",
                    "brakeSurface", "brakeCore", "brakeThermalEfficiency", "brakeSoakRateCs",
                    "ductAirCoolFactor", "ductSoakCondFactor",
                    "driveHeatGate", "driveHeatGateCarcass",
                    "loadN", "loadPct", "peakForce", "longGrip", "latGrip", "lockFade",
                    "wheelSpeedMps", "wheelSpeedMph",
                    "nodeWearPeak", "nodeWearContact", "nodeMuScale", "nodeSlideScale", "nodeMassScale",
                    "nodeOmega", "nodeCamFrac", "nodeCamColScale", "nodeCamArmDeg",
                    "slipEnergy", "longSlip", "sideSlip",
                    "suspCompressionMm", "suspVel", "suspStress", "suspBumpMm", "suspDroopMm", "dynamicRadius",
                    "muStatic", "muSlide", "contactDepth", "rough",
                    "patchFrac", "patchHeatScale", "depthHeatBoost", "hertzArea", "deflArea", "depthBlend",
                    "streetSlipScale", "utilNudge", "dualContactBlend",
                    "airCoolRate", "skinVelCoolScale", "workHeatG0", "slipHeatRate", "workHeatRate",
                    "trackCondMult", "staticCoolRate",
                    "clog", "graining", "blistering", "leak", "waterFilm",
                    "stintFade", "ductPercent", "luaPressure", "nativePressure", "pressureDelta"
                ];

                scope.wheels = [];
                scope.envTemp = 21;
                scope.trackTemp = 21;
                scope.rainState = 0;
                scope.waterFilm = 0;
                scope.totalDownforceKN = "\u20070.00";
                scope.aeroFracPct = 0;
                scope.aeroDragKN = "\u20070.00";
                scope.aeroFrontPct = 0;
                scope.aeroRearPct = 0;
                scope.aeroCopPct = 0;
                scope.aeroNative = false;
                scope.elevationM = 0;
                scope.timeOfDay = "0.00";
                scope.cloudCover = 0;
                scope.packWake = 0;
                scope.packAirDelta = 0;
                scope.streamHz = 30;
                scope.envTempRange = 0;
                scope.stintKm = 0;
                scope.odoKm = 0;
                scope.airspeedMps = 0;
                scope.airspeedMph = 0;
                scope.weightFrontPct = 0;
                scope.weightRearPct = 0;
                scope.weightLeftPct = 0;
                scope.weightRightPct = 0;
                scope.gLong = 0;
                scope.gLat = 0;
                scope.gMag = 0;
                scope.yawRateDeg = 0;
                scope._dfN = 0;
                scope._dragN = 0;
                scope._tod = 0;

                scope.formatProfile = function (profile) {
                    if (!profile) return '';
                    return String(profile).replace(/_/g, ' ');
                };

                // Signed telemetry: stable sign column + no noisy "-0.00" from float dust.
                // Half-LSB snap so parked aero/G don't flash minus zeros and shift neighbors.
                scope.fmtSigned = function (v, digits) {
                    var n = Number(v);
                    if (!isFinite(n)) n = 0;
                    var d = (digits === undefined || digits === null) ? 2 : digits;
                    var eps = Math.pow(10, -d) * 0.5;
                    if (Math.abs(n) < eps) n = 0;
                    var s = n.toFixed(d);
                    if (s.charAt(0) === '-' && Number(s) === 0) {
                        s = s.slice(1);
                    }
                    return (s.charAt(0) === '-' ? '' : '\u2007') + s;
                };

                // Aero % of load: hide sub-0.5% noise (parked / triangulation dust).
                scope.fmtAeroFracPct = function (v) {
                    var n = Number(v);
                    if (!isFinite(n) || Math.abs(n) < 0.5) n = 0;
                    return scope.fmtSigned(n, 1);
                };

                // A1 hybrid: share of Cond drop from node (0=scalar-led, 100=fully node-led).
                scope.a1NodeLeadPct = function (w) {
                    if (!w) return 0;
                    if (w.conditionNodeLead !== undefined && w.conditionNodeLead !== null
                        && isFinite(Number(w.conditionNodeLead)) && Number(w.conditionNodeLead) >= 0) {
                        return Math.max(0, Math.min(100, Number(w.conditionNodeLead)));
                    }
                    var sc = (w.conditionScalar !== undefined && w.conditionScalar !== null)
                        ? Number(w.conditionScalar)
                        : Number(w.condition);
                    var nd = (w.conditionNode !== undefined && w.conditionNode !== null)
                        ? Number(w.conditionNode)
                        : (100 - (Number(w.nodeWearPeak) || 0) * 100);
                    var cond = Number(w.condition);
                    if (!isFinite(sc)) sc = 100;
                    if (!isFinite(nd)) nd = 100;
                    if (!isFinite(cond)) cond = Math.min(sc, nd);
                    var drop = Math.max(0.5, 100 - cond);
                    return Math.max(0, Math.min(100, ((sc - cond) / drop) * 100));
                };

                scope.a1NodeLeadLabel = function (w) {
                    var pct = Math.round(scope.a1NodeLeadPct(w));
                    var cond = Number(w && w.condition);
                    if (!isFinite(cond)) cond = 100;
                    if (cond >= 99.5 && pct < 5) return 'fresh';
                    if (pct >= 85) return 'node ' + pct + '%';
                    if (pct <= 15) return 'scalar';
                    return 'mix n' + pct + '%';
                };

                // Kept for any leftover call sites.
                scope.a1LeadingLabel = function (w) {
                    return scope.a1NodeLeadLabel(w);
                };

                // GT3/ABS: hard scrub with slipE but ω too high for lock arm → cole falls back / idle.
                scope.absHint = function (w) {
                    if (!w) return '';
                    var gate = w.nodeGate || 'idle';
                    if (gate === 'lock' || gate === 'lock+cam' || gate === 'drift' || gate === 'drift+cam') return '';
                    var slip = Number(w.slipEnergy) || 0;
                    var omega = Number(w.nodeOmega) || 0;
                    var lockSrc = w.nodeLockEnergySrc || 'idle';
                    if (slip > 0.18 && omega >= 14) return 'ABS?/no-lock';
                    if (lockSrc === 'slipE' && slip > 0.18) return 'cole→slipE';
                    return '';
                };

                scope.formatPurpose = function (purpose) {
                    if (!purpose) return '';
                    return String(purpose).replace(/_/g, ' ').replace(/\b\w/g, function (c) {
                        return c.toUpperCase();
                    });
                };

                var DUTY_MOD_LABELS = {
                    fwd_slip_softcap: 'FWD slip soft-cap',
                    street_slip_softcap: 'Street slip soft-cap',
                    sport_plus_slip_softcap: 'Sport+ slip soft-cap',
                    street_high_v_damp: 'High-V street damp',
                    undriven_warmup: 'Undriven warm-up',
                    awd_prop_gate: 'AWD prop gate',
                    brake_tire_soak: 'Brake tire soak',
                    duct_tire_side: 'Duct tire-side',
                    soft_sink_damp: 'Soft-sink damp'
                };

                scope.formatDutyMod = function (id) {
                    if (!id) return '';
                    return DUTY_MOD_LABELS[id] || String(id).replace(/_/g, ' ');
                };

                scope.formatDutyMods = function (dutyMods) {
                    if (!dutyMods) return '';
                    var parts = String(dutyMods).split(',');
                    var labels = [];
                    var i, id;
                    for (i = 0; i < parts.length; i++) {
                        id = parts[i].replace(/^\s+|\s+$/g, '');
                        if (!id) continue;
                        labels.push(scope.formatDutyMod(id));
                    }
                    return labels.join(' · ');
                };

                scope.isLargeSkinGap = function (gap) {
                    return Math.abs(gap || 0) > 15;
                };

                scope.pressureBandLabel = function (w) {
                    var opt = (w && (w.targetHotPressure || w.optimalPressure)) || 25;
                    if (opt <= 0) opt = 25;
                    var pressure = (w && w.pressure) || 0;
                    var ratio = pressure / opt;
                    if (pressure < 5) return "FLAT";
                    if (ratio < 0.70) return "LOW";
                    if (ratio < 0.86) return "UNDER";
                    if (ratio <= 1.04) return "OPT";
                    if (ratio <= 1.32) return "WARM+";
                    if (ratio <= 1.55) return "OVER";
                    return "HIGH";
                };

                // |Lua−Nat| for hot write-back convergence (green when tight, amber while catching up)
                scope.pressureDeltaAbs = function (w) {
                    var d = (w && w.pressureDelta !== undefined)
                        ? w.pressureDelta
                        : ((w && w.luaPressure !== undefined ? w.luaPressure : 0) - (w && w.nativePressure !== undefined ? w.nativePressure : 0));
                    return Math.abs(d || 0).toFixed(1);
                };
                scope.pressureConvColor = function (w) {
                    var d = Math.abs((w && w.pressureDelta !== undefined)
                        ? w.pressureDelta
                        : ((w && w.luaPressure !== undefined ? w.luaPressure : 0) - (w && w.nativePressure !== undefined ? w.nativePressure : 0)));
                    if (d <= 0.2) return "#10b981"; // converged (within ~deadband)
                    if (d <= 1.0) return "#cbd5e1"; // closing in
                    return "#f59e0b"; // warm-up lag / write-back catching Nat
                };

                scope.tempCategoryColor = function (cat) {
                    if (cat === 'Cold') return '#38bdf8';
                    if (cat === 'Hot') return '#ef4444';
                    return '#10b981';
                };

                scope.isExcessiveCamber = function (camber) {
                    return Math.abs(camber || 0) > 3.0;
                };

                scope.getConditionColor = function (condition) {
                    if (condition === undefined) return "#10b981";
                    var ratio = condition / 100;
                    if (ratio > 0.7) return "#10b981";
                    if (ratio > 0.4) return "#f59e0b";
                    return "#ef4444";
                };

                scope.getGripColor = function (grip) {
                    if (grip === undefined) return "#f1f5f9";
                    if (grip >= 0.95) return "#10b981";
                    if (grip >= 0.85) return "#a3e635";
                    if (grip >= 0.70) return "#f59e0b";
                    return "#ef4444";
                };

                scope.getDiagnosticColor = function (value) {
                    if (!value || value <= 5) return "#cbd5e1";
                    if (value <= 25) return "#a3e635";
                    if (value <= 60) return "#f59e0b";
                    return "#ef4444";
                };

                scope.wearRingColor = function (pct) {
                    var p = Math.min(100, Math.max(0, pct || 0));
                    if (p < 1) return "#334155";
                    if (p < 8) return "#475569";
                    var hue = 48 - (p / 100) * 48;
                    var lit = 42 + Math.min(18, p * 0.2);
                    return "hsl(" + Math.round(hue) + ", 90%, " + Math.round(lit) + "%)";
                };

                scope.ringSample = function (ring, i) {
                    if (!ring) return 0;
                    if (ring[i] !== undefined && ring[i] !== null) return ring[i];
                    if (ring[i + 1] !== undefined && ring[i + 1] !== null) return ring[i + 1];
                    return 0;
                };

                scope.wearRingGradient = function (w) {
                    var ring = (w && w.nodeWearRing) || [];
                    var n = w && w.nodeWearRingN ? w.nodeWearRingN : 0;
                    if (!n) {
                        n = ring.length || 0;
                        if ((!ring[0] && ring[0] !== 0) && ring[1] !== undefined) n = Math.max(n, Object.keys(ring).length);
                    }
                    if (!n || n < 1) return "#1e293b";
                    var parts = [];
                    var step = 360 / n;
                    var i, pct, c0;
                    for (i = 0; i < n; i++) {
                        pct = scope.ringSample(ring, i);
                        c0 = scope.wearRingColor(pct);
                        parts.push(c0 + " " + (i * step).toFixed(2) + "deg " + ((i + 1) * step).toFixed(2) + "deg");
                    }
                    return "conic-gradient(from -90deg, " + parts.join(", ") + ")";
                };

                scope.getSurfaceDamageColor = function (value) {
                    if (!value || value <= 5) return "#cbd5e1";
                    if (value <= 25) return "#38bdf8";
                    if (value <= 60) return "#f59e0b";
                    return "#ef4444";
                };

                scope.getInflationColor = function (pressure, optimalPressure) {
                    if (pressure === undefined) return "#f1f5f9";
                    var opt = optimalPressure || 25;
                    if (opt <= 0) opt = 25;
                    var ratio = pressure / opt;
                    if (pressure < 5) return "#ef4444";
                    if (ratio < 0.70) return "#38bdf8";
                    if (ratio < 0.86) return "#a3e635";
                    if (ratio <= 1.04) return "#10b981";
                    if (ratio <= 1.32) return "#34d399";
                    if (ratio <= 1.55) return "#f59e0b";
                    return "#ef4444";
                };

                scope.getTuningWarning = function (initialPressure, optimalPressure) {
                    var initialPres = initialPressure || 25;
                    var optPres = optimalPressure || 25;
                    var underLimit = Math.min(optPres * 0.86, optPres - 4);
                    var overLimit = Math.max(optPres * 1.32, optPres + 8);
                    if (initialPres < underLimit) {
                        return "UNDERINFLATED";
                    } else if (initialPres > overLimit) {
                        return "OVERINFLATED";
                    }
                    return "";
                };

                // Cold-set vs hot-target band: short UNDER/OVER chip (hidden when empty).
                scope.coldSetWarnChip = function (w) {
                    var warn = scope.getTuningWarning(
                        (w && (w.coldPressure || w.initialPressure)) || 0,
                        (w && (w.targetHotPressure || w.optimalPressure)) || 0
                    );
                    if (warn === "UNDERINFLATED") return "UNDER";
                    if (warn === "OVERINFLATED") return "OVER";
                    return "";
                };
                scope.coldSetWarnStyle = function (w) {
                    var chip = scope.coldSetWarnChip(w);
                    if (chip === "UNDER") {
                        return {
                            color: "#38bdf8",
                            "border-color": "rgba(56,189,248,0.35)",
                            background: "rgba(56,189,248,0.12)"
                        };
                    }
                    return {
                        color: "#f59e0b",
                        "border-color": "rgba(245,158,11,0.35)",
                        background: "rgba(245,158,11,0.12)"
                    };
                };

                scope.getTempColor = function (tempVal, working_temp) {
                    if (tempVal === undefined) return "hsla(240, 80%, 45%, 1)";
                    var r = tempVal / (working_temp || 85);
                    var hue;
                    if (r < 0.75) {
                        var tCold = Math.min(Math.max((r - 0.4) / 0.35, 0), 1);
                        tCold = tCold * tCold * (3 - 2 * tCold);
                        hue = 240 - tCold * 120;
                    } else if (r <= 1.10) {
                        hue = 120;
                    } else {
                        var tHot = Math.min(Math.max((r - 1.10) / 0.30, 0), 1);
                        tHot = tHot * tHot * (3 - 2 * tHot);
                        hue = 120 - tHot * 120;
                    }
                    return "hsla(" + Math.round(hue) + ", 80%, 45%, 1)";
                };

                function lerpNum(cur, tgt, alpha) {
                    if (tgt === undefined || tgt === null) return cur;
                    if (cur === undefined || cur === null) return tgt;
                    var next = cur + (tgt - cur) * alpha;
                    return Math.abs(tgt - next) < LERP_EPS ? tgt : next;
                }

                function isLerpKey(k) {
                    return WHEEL_LERP_KEYS.indexOf(k) !== -1;
                }

                function prepareWheelTemps(w) {
                    var t = w.temp || [];
                    w.surfaceTemps = [t[0] || 0, t[1] || 0, t[2] || 0];
                    w.carcassTemps = [t[3] || 0, t[4] || 0, t[5] || 0];
                    if (w.rimTemp === undefined) w.rimTemp = t[6] || 0;
                    if (w.airTemp === undefined) w.airTemp = t[7] || 0;
                    if (!w.zoneCondition || w.zoneCondition.length !== 3) {
                        var c = w.condition !== undefined ? w.condition : 100;
                        w.zoneCondition = [c, c, c];
                    }
                }

                function copyArr3(src, fallback) {
                    var a = src || fallback || [0, 0, 0];
                    return [a[0] || 0, a[1] || 0, a[2] || 0];
                }

                function copyWearRing(src) {
                    if (!src || !src.length) return [];
                    var out = [];
                    var i;
                    for (i = 0; i < src.length; i++) out[i] = src[i] || 0;
                    return out;
                }

                // Full shallow wheel copy so Heavy keeps every stream field; arrays are cloned.
                function cloneWheel(src) {
                    var dst = {};
                    var k;
                    for (k in src) {
                        if (!Object.prototype.hasOwnProperty.call(src, k)) continue;
                        if (k === "surfaceTemps" || k === "carcassTemps" || k === "zoneCondition" || k === "temp" || k === "nodeWearRing") continue;
                        dst[k] = src[k];
                    }
                    dst.temp = (src.temp && src.temp.slice) ? src.temp.slice() : [];
                    dst.surfaceTemps = copyArr3(src.surfaceTemps);
                    dst.carcassTemps = copyArr3(src.carcassTemps);
                    dst.zoneCondition = copyArr3(src.zoneCondition, [100, 100, 100]);
                    dst.nodeWearRing = copyWearRing(src.nodeWearRing);
                    return dst;
                }

                function syncNonLerp(dst, src) {
                    var k;
                    for (k in src) {
                        if (!Object.prototype.hasOwnProperty.call(src, k)) continue;
                        if (isLerpKey(k)) continue;
                        if (k === "surfaceTemps" || k === "carcassTemps" || k === "zoneCondition" || k === "temp" || k === "nodeWearRing") continue;
                        dst[k] = src[k];
                    }
                    dst.nodeWearRing = copyWearRing(src.nodeWearRing);
                }

                function setTargetWheel(dst, src) {
                    var k, i;
                    syncNonLerp(dst, src);
                    for (i = 0; i < WHEEL_LERP_KEYS.length; i++) {
                        k = WHEEL_LERP_KEYS[i];
                        dst[k] = src[k] !== undefined && src[k] !== null ? src[k] : 0;
                    }
                    dst.temp = (src.temp && src.temp.slice) ? src.temp.slice() : [];
                    dst.surfaceTemps = copyArr3(src.surfaceTemps);
                    dst.carcassTemps = copyArr3(src.carcassTemps);
                    dst.zoneCondition = copyArr3(src.zoneCondition, [100, 100, 100]);
                    dst.nodeWearRing = copyWearRing(src.nodeWearRing);
                }

                function isAppVisible() {
                    if (document.hidden) return false;
                    var el = element[0];
                    if (!el) return false;
                    // Detached / display:none apps have no layout box — skip RAF work.
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

                function applyDisplayMeta() {
                    scope.totalDownforceKN = scope.fmtSigned((scope._dfN || 0) / 1000, 2);
                    scope.aeroDragKN = scope.fmtSigned((scope._dragN || 0) / 1000, 2);
                    scope.timeOfDay = Number(scope._tod || 0).toFixed(2);
                }

                function lerpDisplay(alpha) {
                    var moved = false;
                    var i, j, k, prev, d, t;

                    prev = scope.envTemp;
                    scope.envTemp = lerpNum(scope.envTemp, targetMeta.envTemp, alpha);
                    if (scope.envTemp !== prev) moved = true;

                    prev = scope.trackTemp;
                    scope.trackTemp = lerpNum(scope.trackTemp, targetMeta.trackTemp, alpha);
                    if (scope.trackTemp !== prev) moved = true;

                    prev = scope.rainState;
                    scope.rainState = lerpNum(scope.rainState, targetMeta.rainState, alpha);
                    if (scope.rainState !== prev) moved = true;

                    prev = scope.waterFilm;
                    scope.waterFilm = lerpNum(scope.waterFilm, targetMeta.waterFilm, alpha);
                    if (scope.waterFilm !== prev) moved = true;

                    prev = scope._dfN;
                    scope._dfN = lerpNum(scope._dfN || 0, targetMeta.totalDownforceN, alpha);
                    if (scope._dfN !== prev) moved = true;

                    prev = scope.aeroFracPct;
                    scope.aeroFracPct = lerpNum(scope.aeroFracPct, targetMeta.aeroFracPct, alpha);
                    if (scope.aeroFracPct !== prev) moved = true;

                    prev = scope._dragN;
                    scope._dragN = lerpNum(scope._dragN || 0, targetMeta.aeroDragN, alpha);
                    if (scope._dragN !== prev) moved = true;

                    prev = scope.aeroFrontPct;
                    scope.aeroFrontPct = lerpNum(scope.aeroFrontPct, targetMeta.aeroFrontPct, alpha);
                    if (scope.aeroFrontPct !== prev) moved = true;

                    prev = scope.aeroRearPct;
                    scope.aeroRearPct = lerpNum(scope.aeroRearPct, targetMeta.aeroRearPct, alpha);
                    if (scope.aeroRearPct !== prev) moved = true;

                    prev = scope.aeroCopPct;
                    scope.aeroCopPct = lerpNum(scope.aeroCopPct, targetMeta.aeroCopPct, alpha);
                    if (scope.aeroCopPct !== prev) moved = true;

                    prev = scope.elevationM;
                    scope.elevationM = lerpNum(scope.elevationM, targetMeta.elevationM, alpha);
                    if (scope.elevationM !== prev) moved = true;

                    prev = scope._tod;
                    scope._tod = lerpNum(scope._tod || 0, targetMeta.timeOfDay, alpha);
                    if (scope._tod !== prev) moved = true;

                    prev = scope.cloudCover;
                    scope.cloudCover = lerpNum(scope.cloudCover, targetMeta.cloudCover, alpha);
                    if (scope.cloudCover !== prev) moved = true;

                    prev = scope.packWake;
                    scope.packWake = lerpNum(scope.packWake, targetMeta.packWake, alpha);
                    if (scope.packWake !== prev) moved = true;

                    prev = scope.packAirDelta;
                    scope.packAirDelta = lerpNum(scope.packAirDelta, targetMeta.packAirDelta, alpha);
                    if (scope.packAirDelta !== prev) moved = true;

                    prev = scope.envTempRange;
                    scope.envTempRange = lerpNum(scope.envTempRange, targetMeta.envTempRange, alpha);
                    if (scope.envTempRange !== prev) moved = true;
                    prev = scope.stintKm;
                    scope.stintKm = lerpNum(scope.stintKm, targetMeta.stintKm, alpha);
                    if (scope.stintKm !== prev) moved = true;
                    prev = scope.odoKm;
                    scope.odoKm = lerpNum(scope.odoKm, targetMeta.odoKm, alpha);
                    if (scope.odoKm !== prev) moved = true;

                    prev = scope.airspeedMps;
                    scope.airspeedMps = lerpNum(scope.airspeedMps, targetMeta.airspeedMps, alpha);
                    if (scope.airspeedMps !== prev) moved = true;

                    prev = scope.airspeedMph;
                    scope.airspeedMph = lerpNum(scope.airspeedMph, targetMeta.airspeedMph, alpha);
                    if (scope.airspeedMph !== prev) moved = true;

                    prev = scope.weightFrontPct;
                    scope.weightFrontPct = lerpNum(scope.weightFrontPct, targetMeta.weightFrontPct, alpha);
                    if (scope.weightFrontPct !== prev) moved = true;

                    prev = scope.weightRearPct;
                    scope.weightRearPct = lerpNum(scope.weightRearPct, targetMeta.weightRearPct, alpha);
                    if (scope.weightRearPct !== prev) moved = true;

                    prev = scope.weightLeftPct;
                    scope.weightLeftPct = lerpNum(scope.weightLeftPct, targetMeta.weightLeftPct, alpha);
                    if (scope.weightLeftPct !== prev) moved = true;

                    prev = scope.weightRightPct;
                    scope.weightRightPct = lerpNum(scope.weightRightPct, targetMeta.weightRightPct, alpha);
                    if (scope.weightRightPct !== prev) moved = true;

                    prev = scope.gLong;
                    scope.gLong = lerpNum(scope.gLong, targetMeta.gLong, alpha);
                    if (scope.gLong !== prev) moved = true;

                    prev = scope.gLat;
                    scope.gLat = lerpNum(scope.gLat, targetMeta.gLat, alpha);
                    if (scope.gLat !== prev) moved = true;

                    prev = scope.gMag;
                    scope.gMag = lerpNum(scope.gMag, targetMeta.gMag, alpha);
                    if (scope.gMag !== prev) moved = true;

                    prev = scope.yawRateDeg;
                    scope.yawRateDeg = lerpNum(scope.yawRateDeg, targetMeta.yawRateDeg, alpha);
                    if (scope.yawRateDeg !== prev) moved = true;

                    var n = Math.min(scope.wheels.length, targetWheels.length);
                    for (i = 0; i < n; i++) {
                        d = scope.wheels[i];
                        t = targetWheels[i];
                        syncNonLerp(d, t);
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

                            prev = d.zoneCondition[j];
                            d.zoneCondition[j] = lerpNum(d.zoneCondition[j], t.zoneCondition[j], alpha);
                            if (d.zoneCondition[j] !== prev) moved = true;
                        }
                    }
                    applyDisplayMeta();
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
                    // Throttle digests: RAF keeps lerping the model; Angular rebinds at ~20 Hz.
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
                function resetRespinStreamBind() {
                    boundVehId = null;
                    boundResetGen = null;
                }
                function acceptRespinStream(dataStream) {
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
                function isRespinLifeReset(dataStream) {
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
                    if (!acceptRespinStream(dataStream)) return;

                    var src = dataStream.data;
                    var count = src.length;
                    var lifeReset = isRespinLifeReset(dataStream);
                    var structural = lifeReset || (scope.wheels.length !== count);
                    var i, w;

                    for (i = 0; i < count; i++) {
                        prepareWheelTemps(src[i]);
                    }

                    targetMeta.envTemp = dataStream.envTemp !== undefined ? dataStream.envTemp : targetMeta.envTemp;
                    targetMeta.trackTemp = dataStream.trackTemp !== undefined ? dataStream.trackTemp : targetMeta.trackTemp;
                    targetMeta.rainState = dataStream.rainState !== undefined ? dataStream.rainState : targetMeta.rainState;
                    targetMeta.waterFilm = dataStream.waterFilm !== undefined ? dataStream.waterFilm : targetMeta.waterFilm;
                    targetMeta.totalDownforceN = dataStream.totalDownforceN !== undefined ? dataStream.totalDownforceN : targetMeta.totalDownforceN;
                    targetMeta.aeroFracPct = dataStream.aeroFracPct !== undefined ? dataStream.aeroFracPct : targetMeta.aeroFracPct;
                    targetMeta.aeroDragN = dataStream.aeroDragN !== undefined ? dataStream.aeroDragN : targetMeta.aeroDragN;
                    targetMeta.aeroFrontPct = dataStream.aeroFrontPct !== undefined ? dataStream.aeroFrontPct : targetMeta.aeroFrontPct;
                    targetMeta.aeroRearPct = dataStream.aeroRearPct !== undefined ? dataStream.aeroRearPct : targetMeta.aeroRearPct;
                    targetMeta.aeroCopPct = dataStream.aeroCopPct !== undefined ? dataStream.aeroCopPct : targetMeta.aeroCopPct;
                    if (dataStream.aeroNative !== undefined) scope.aeroNative = !!dataStream.aeroNative;
                    targetMeta.elevationM = dataStream.elevationM !== undefined ? dataStream.elevationM : targetMeta.elevationM;
                    targetMeta.timeOfDay = dataStream.timeOfDay !== undefined ? Number(dataStream.timeOfDay) : targetMeta.timeOfDay;
                    targetMeta.cloudCover = dataStream.cloudCover !== undefined ? dataStream.cloudCover : targetMeta.cloudCover;
                    targetMeta.packWake = dataStream.packWake !== undefined ? dataStream.packWake : targetMeta.packWake;
                    targetMeta.packAirDelta = dataStream.packAirDelta !== undefined ? dataStream.packAirDelta : targetMeta.packAirDelta;
                    targetMeta.envTempRange = dataStream.envTempRange !== undefined ? dataStream.envTempRange : targetMeta.envTempRange;
                    targetMeta.stintKm = dataStream.stintKm !== undefined ? dataStream.stintKm : targetMeta.stintKm;
                    targetMeta.odoKm = dataStream.odoKm !== undefined ? dataStream.odoKm : targetMeta.odoKm;
                    targetMeta.airspeedMps = dataStream.airspeedMps !== undefined ? dataStream.airspeedMps : targetMeta.airspeedMps;
                    targetMeta.airspeedMph = dataStream.airspeedMph !== undefined ? dataStream.airspeedMph : targetMeta.airspeedMph;
                    targetMeta.weightFrontPct = dataStream.weightFrontPct !== undefined ? dataStream.weightFrontPct : targetMeta.weightFrontPct;
                    targetMeta.weightRearPct = dataStream.weightRearPct !== undefined ? dataStream.weightRearPct : targetMeta.weightRearPct;
                    targetMeta.weightLeftPct = dataStream.weightLeftPct !== undefined ? dataStream.weightLeftPct : targetMeta.weightLeftPct;
                    targetMeta.weightRightPct = dataStream.weightRightPct !== undefined ? dataStream.weightRightPct : targetMeta.weightRightPct;
                    targetMeta.gLong = dataStream.gLong !== undefined ? dataStream.gLong : targetMeta.gLong;
                    targetMeta.gLat = dataStream.gLat !== undefined ? dataStream.gLat : targetMeta.gLat;
                    targetMeta.gMag = dataStream.gMag !== undefined ? dataStream.gMag : targetMeta.gMag;
                    targetMeta.yawRateDeg = dataStream.yawRateDeg !== undefined ? dataStream.yawRateDeg : targetMeta.yawRateDeg;

                    if (dataStream.streamHz !== undefined) scope.streamHz = dataStream.streamHz;

                    if (structural) {
                        // Wheel-count change or same-id resetGen bump: snap cold, drop RAF lerp.
                        stopRaf();
                        targetWheels = [];
                        var wheels = [];
                        for (i = 0; i < count; i++) {
                            w = src[i] || {};
                            targetWheels.push(cloneWheel(w));
                            wheels.push(cloneWheel(w));
                        }
                        scope.wheels = wheels;
                        scope.envTemp = targetMeta.envTemp;
                        scope.trackTemp = targetMeta.trackTemp;
                        scope.rainState = targetMeta.rainState;
                        scope.waterFilm = targetMeta.waterFilm;
                        scope._dfN = targetMeta.totalDownforceN;
                        scope.aeroFracPct = targetMeta.aeroFracPct;
                        scope._dragN = targetMeta.aeroDragN;
                        scope.aeroFrontPct = targetMeta.aeroFrontPct;
                        scope.aeroRearPct = targetMeta.aeroRearPct;
                        scope.aeroCopPct = targetMeta.aeroCopPct;
                        scope.elevationM = targetMeta.elevationM;
                        scope._tod = targetMeta.timeOfDay;
                        scope.cloudCover = targetMeta.cloudCover;
                        scope.packWake = targetMeta.packWake;
                        scope.packAirDelta = targetMeta.packAirDelta;
                        scope.envTempRange = targetMeta.envTempRange;
                        scope.stintKm = targetMeta.stintKm;
                        scope.odoKm = targetMeta.odoKm;
                        scope.airspeedMps = targetMeta.airspeedMps;
                        scope.airspeedMph = targetMeta.airspeedMph;
                        scope.weightFrontPct = targetMeta.weightFrontPct;
                        scope.weightRearPct = targetMeta.weightRearPct;
                        scope.weightLeftPct = targetMeta.weightLeftPct;
                        scope.weightRightPct = targetMeta.weightRightPct;
                        scope.gLong = targetMeta.gLong;
                        scope.gLat = targetMeta.gLat;
                        scope.gMag = targetMeta.gMag;
                        scope.yawRateDeg = targetMeta.yawRateDeg;
                        applyDisplayMeta();
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

                scope.$on("VehicleChange", resetRespinStreamBind);
                scope.$on("VehicleFocusChanged", resetRespinStreamBind);
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
