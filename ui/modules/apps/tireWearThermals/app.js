angular.module("beamng.apps")
    .directive("tireWearThermals", ["$injector", function ($injector) {
        return {
            template: '<canvas width="220" height="220"></canvas>',
            replace: true,
            restrict: "EA",
            link: function (scope, element, attrs) {
                var StreamsManager = window.StreamsManager || ($injector.has("StreamsManager") ? $injector.get("StreamsManager") : null);
                var streamsList = ["TireWearThermals"];
                
                if (StreamsManager) {
                    StreamsManager.add(streamsList);
                }

                scope.$on("$destroy", function () {
                    if (StreamsManager) {
                        StreamsManager.remove(streamsList);
                    }
                });

                var c = element[0];
                var ctx = c.getContext("2d");

                scope.$on('app:resized', function (event, data) {
                    c.width = data.width || 220;
                    c.height = data.height || 220;
                });

                // Standard border-radius drawing utility
                function roundRect(ctx, x, y, width, height, radius, fill, stroke) {
                    if (radius === undefined) radius = 5;
                    if (fill === undefined) fill = false;
                    if (stroke === undefined) stroke = true;

                    if (typeof radius === 'number') {
                        radius = { tl: radius, tr: radius, br: radius, bl: radius };
                    } else {
                        radius = angular.extend({ tl: 0, tr: 0, br: 0, bl: 0 }, radius);
                    }
                    ctx.beginPath();
                    ctx.moveTo(x + radius.tl, y);
                    ctx.lineTo(x + width - radius.tr, y);
                    ctx.quadraticCurveTo(x + width, y, x + width, y + radius.tr);
                    ctx.lineTo(x + width, y + height - radius.br);
                    ctx.quadraticCurveTo(x + width, y + height, x + width - radius.br, y + height);
                    ctx.lineTo(x + radius.bl, y + height);
                    ctx.quadraticCurveTo(x, y + height, x, y + height - radius.bl);
                    ctx.lineTo(x, y + radius.tl);
                    ctx.quadraticCurveTo(x, y, x + radius.tl, y);
                    ctx.closePath();
                    if (fill) {
                        ctx.fill();
                    }
                    if (stroke) {
                        ctx.stroke();
                    }
                }

                // Resolves HSL thermal gradient with smoothstep transitions
                function getTempColor(tempVal, working_temp) {
                    var r = tempVal / (working_temp || 85);
                    var hue;
                    
                    if (r < 0.75) {
                        // Cold to Optimal transition: Blue (240) to Green (120)
                        var t = Math.min(Math.max((r - 0.4) / 0.35, 0), 1);
                        t = t * t * (3 - 2 * t);
                        hue = 240 + t * (120 - 240);
                    } else if (r <= 1.15) {
                        // Optimal zone (Green)
                        hue = 120;
                    } else {
                        // Overheated transition: Green to Red (120 to 0)
                        var t = Math.min(1.0, (r - 1.15) / 0.35);
                        t = t * t * (3 - 2 * t);
                        hue = 120 - t * 120;
                    }
                    
                    return "hsla(" + Math.round(hue) + ",85%,52%,1)";
                }

                function drawWheelData(d, tyreNumber, wheelCount) {
                    var name = d.name || "unknown";
                    var temps = d.temp;
                    var working_temp = d.working_temp;
                    var condition = d.condition;
                    var camber = d.camber;
                    var pressure = d.pressure;
                    var initialPressure = d.initialPressure;
                    var surfaceDamage = d.surfaceDamage;

                    if (!temps || temps.length === 0) {
                        temps = [0, 0, 0, 0, 0, 0, 0, 0];
                    }

                    if (condition === undefined) condition = 100;
                    camber = camber || 0;
                    // A1 / A3 stream: O|M|I from zoneCondition; header condition = display hybrid
                    // min(scalar, node). Cond % does not tax grip while node spike on.
                    var zc = d.zoneCondition || [];
                    var zoneConds = [
                        (zc[0] !== undefined && zc[0] !== null) ? zc[0] : condition,
                        (zc[1] !== undefined && zc[1] !== null) ? zc[1] : condition,
                        (zc[2] !== undefined && zc[2] !== null) ? zc[2] : condition
                    ];

                    ctx.textAlign = 'center';

                    // Robust horizontal coordinate (Left/Right Side detection)
                    var right = (tyreNumber % 2 === 1) ? 1 : 0;
                    var nameUpper = name.toUpperCase();
                    var testStr = nameUpper;
                    
                    if (nameUpper.length > 1 && (nameUpper[0] === 'F' || nameUpper[0] === 'R')) {
                        testStr = nameUpper.substring(1);
                    }
                    
                    if (testStr.indexOf("R") !== -1) {
                        right = 1;
                    } else if (testStr.indexOf("L") !== -1) {
                        right = 0;
                    }

                    // Robust dynamic axle coordinate assignment (Row detection)
                    var back = 0;
                    if (nameUpper.indexOf("F") === 0) {
                        back = 0;
                    } else if (nameUpper.indexOf("R") === 0) {
                        var axleNumMatch = nameUpper.match(/\d+/);
                        if (axleNumMatch) {
                            back = parseInt(axleNumMatch[0], 10);
                        } else {
                            back = 1;
                        }
                    } else {
                        back = Math.floor(tyreNumber / 2);
                    }

                    var axleCount = Math.max(2, Math.ceil(wheelCount / 2));
                    var pad = Math.max(6, Math.min(c.width, c.height) * 0.035);
                    var gapX = Math.max(8, c.width * 0.04);
                    var gapY = Math.max(10, c.height * 0.045);
                    var colW = (c.width - pad * 2 - gapX) / 2;
                    var rowH = (c.height - pad * 2 - gapY * (axleCount - 1)) / axleCount;

                    var x = pad + right * (colW + gapX);
                    var y = pad + back * (rowH + gapY);
                    var cx = x + colW * 0.5;

                    // Reserve vertical bands inside the cell so text/triangles never collide
                    var headerH = Math.max(12, rowH * 0.16);
                    var footerH = Math.max(12, rowH * 0.16);
                    var camberGap = Math.max(5, rowH * 0.05);
                    var treadY = y + headerH + camberGap;
                    var treadH = Math.max(18, rowH - headerH - footerH - camberGap * 2);
                    var treadW = colW;

                    // 1. Header Text: Wheel Name & Condition (e.g., FL | 98%)
                    ctx.fillStyle = "#ffffff";
                    var headerSize = Math.max(Math.min(colW / 12.0, 10.0), 7.0);
                    ctx.font = 'bold ' + headerSize + 'pt "Lucida Console", Monaco, monospace';
                    var headerText = name.toUpperCase() + " | " + Math.ceil(condition) + "%";
                    ctx.fillText(headerText, cx, y + headerH * 0.72);

                    // 2. Draw Tire Tread Rings
                    var segGap = 2;
                    var sectionWidth = (treadW - segGap * 2) / 3.0;
                    for (var i = 0; i < 3; i++) {
                        var tempVal = temps[i] || 0;
                        var sectionColor = getTempColor(tempVal, working_temp);

                        var crad = Math.min(5.0, sectionWidth * 0.25);
                        var radius = { tl: 0, tr: 0, br: 0, bl: 0 };
                        if (i === 0) {
                            radius = { tl: crad, tr: 0, br: 0, bl: crad };
                        } else if (i === 2) {
                            radius = { tl: 0, tr: crad, br: crad, bl: 0 };
                        }

                        var sectionXOffset = (sectionWidth + segGap) * i;
                        
                        // Draw empty background representing tread loss
                        ctx.fillStyle = "rgba(15, 23, 42, 0.65)";
                        ctx.beginPath();
                        ctx.rect(x + sectionXOffset, treadY, sectionWidth, treadH);
                        ctx.fill();

                        // Fill color representing remaining tread (per O|M|I zone)
                        var zoneCond = zoneConds[i];
                        if (zoneCond === undefined || zoneCond === null) zoneCond = condition;
                        if (zoneCond > 1) {
                            var ft = 1.0 - (zoneCond / 100);
                            ctx.fillStyle = sectionColor;
                            ctx.beginPath();
                            ctx.rect(x + sectionXOffset, treadY + treadH * ft, sectionWidth, treadH - treadH * ft);
                            ctx.fill();
                        }
                        
                        ctx.lineWidth = "2";
                        ctx.strokeStyle = "rgba(0,0,0,1)";
                        roundRect(ctx, x + sectionXOffset, treadY, sectionWidth, treadH, radius, false, true);

                        // Overlay Temperature centered vertically inside the block
                        ctx.fillStyle = "#ffffff";
                        var font_size = Math.max(Math.min(colW / 16.0 * 2.6, 11.0), 7.0);
                        ctx.font = 'bold ' + font_size + 'pt "Lucida Console", Monaco, monospace';
                        ctx.fillText("" + Math.floor(tempVal), x + sectionXOffset + (sectionWidth / 2), treadY + treadH / 2 + (font_size / 2.2));
                    }

                    // 3. Draw Camber Triangle Indicators (bound-clamped within the tread width)
                    var triX = x + treadW * 0.5 + treadW * (camber * 0.2 * 0.5);
                    var safetyMargin = Math.max(5, sectionWidth * 0.15);
                    triX = Math.max(x + safetyMargin, Math.min(x + treadW - safetyMargin, triX));

                    ctx.fillStyle = "rgba(239, 68, 68, 0.9)";
                    ctx.beginPath();
                    ctx.moveTo(triX, treadY - 1);
                    ctx.lineTo(triX - 4, treadY - 6);
                    ctx.lineTo(triX + 4, treadY - 6);
                    ctx.fill();

                    ctx.beginPath();
                    ctx.moveTo(triX, treadY + treadH + 1);
                    ctx.lineTo(triX - 4, treadY + treadH + 6);
                    ctx.lineTo(triX + 4, treadY + treadH + 6);
                    ctx.fill();

                    // 4. Footer Text: Pressure with Context-Aware Highlight
                    var pres = (pressure !== undefined) ? pressure : 25;
                    var initPres = initialPressure || 25;
                    var isLow = (pres < initPres * 0.8) || (pres < 10);
                    var isHigh = (pres > initPres * 1.3);
                    
                    ctx.fillStyle = isLow ? "#38bdf8" : (isHigh ? "#ef4444" : "#e2e8f0");
                    var infoFontSize = Math.max(Math.min(colW / 18.0 * 2.4, 10.0), 6.5);
                    ctx.font = 'bold ' + infoFontSize + 'pt "Lucida Console", Monaco, monospace';
                    
                    // Show a warning indicator if surface damage or tread is severe
                    var warningTag = "";
                    if ((surfaceDamage && surfaceDamage > 25) || (condition < 35)) {
                        warningTag = "⚠ ";
                        ctx.fillStyle = "#ffaa44";
                    }

                    var footerText = warningTag + Math.round(pres) + " PSI";
                    ctx.fillText(footerText, cx, y + rowH - footerH * 0.25);
                }

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

                function renderData(dataStream) {
                    if (!acceptNtfStream(dataStream)) return;
                    isNtfLifeReset(dataStream);

                    ctx.setTransform(1, 0, 0, 1, 0, 0); 
                    ctx.clearRect(0, 0, c.width, c.height);
                    ctx.textAlign = 'center';

                    var wheelCount = dataStream.data.length;
                    for (var i = 0; i < wheelCount; i++) {
                        var d = dataStream.data[i];
                        if (d) {
                            drawWheelData(d, i, wheelCount);
                        }
                    }
                }

                scope.$on("VehicleChange", resetNtfStreamBind);
                scope.$on("VehicleFocusChanged", resetNtfStreamBind);
                scope.$on("TireWearThermals", function (event, dataStream) {
                    renderData(dataStream);
                });

                scope.$on("streamsUpdate", function (event, streams) {
                    if (streams && streams.TireWearThermals) {
                        renderData(streams.TireWearThermals);
                    }
                });
            }
        };
    }]);