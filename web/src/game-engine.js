export class GameEngine {
    constructor() {
        this.isPlaying = false;
        this.cats = [];
        this.yarns = [];

        // Данные гироскопа
        this.tilt = { x: 0, y: 0 };
        this.calibration = null; // Для запоминания начального угла телефона
        this.isCalibrated = false;

                // Делаем радиусы более точными (в 2 раза меньше)
        this.yarnRadius = 0.025; // Радиус самого клубка
        this.catRadius = 0.05;   // Радиус тела кота  // Уменьшили, чтобы соответствовало визуальному размеру кота

        this.boundOrientation = this.handleOrientation.bind(this);
        this.boundFrame = this.gameLoop.bind(this);
        this.rafId = null;
    }

    // start() {
    //     this.isPlaying = true;
    //     this.isCalibrated = false;
    //     this.generateLevel();
    //
    //     window.addEventListener('deviceorientation', this.boundOrientation);
    //     this.rafId = requestAnimationFrame(this.boundFrame);
    //
    //     console.log("[GameEngine] Игра запущена. Наклоняйте телефон (или используйте стрелки).");
    // }

    async start() {
        this.isPlaying = true;
        this.isCalibrated = false;
        this.generateLevel();

        // ЗАПРОС РАЗРЕШЕНИЯ ДЛЯ iOS 13+
        if (typeof DeviceOrientationEvent !== 'undefined' && typeof DeviceOrientationEvent.requestPermission === 'function') {
            try {
                const permission = await DeviceOrientationEvent.requestPermission();
                if (permission === 'granted') {
                    window.addEventListener('deviceorientation', this.boundOrientation);
                } else {
                    console.warn("Пользователь отклонил доступ к гироскопу. Управление стрелками недоступно.");
                }
            } catch (error) {
                console.error("Ошибка запроса гироскопа:", error);
            }
        } else {
            // Для Android и старых iOS разрешение не требуется
            window.addEventListener('deviceorientation', this.boundOrientation);
        }

        this.rafId = requestAnimationFrame(this.boundFrame);
        console.log("[GameEngine] Игра запущена.");
    }

    stop() {
        this.isPlaying = false;
        window.removeEventListener('deviceorientation', this.boundOrientation);
        if (this.rafId) cancelAnimationFrame(this.rafId);
        window.CatAnimation.hide();
        console.log("[GameEngine] Игра остановлена.");
    }

    handleOrientation(event) {
        if (!this.isPlaying || event.gamma === null || event.beta === null) return;

        // Калибровка: запоминаем положение телефона при первом событии
        if (!this.isCalibrated) {
            this.calibration = { x: event.gamma, y: event.beta };
            this.isCalibrated = true;
            return;
        }

        // Вычисляем отклонение от начального положения
        this.tilt.x = (event.gamma - this.calibration.x) / 45;
        // На iOS/Android beta часто смещена (телефон держат под углом ~45-90 градусов)
        this.tilt.y = (event.beta - this.calibration.y) / 45;
    }

    // Фоллбэк для тестирования в браузере с клавиатуры
    handleKeyboard(keys) {
        if (!this.isPlaying) return;
        // Если гироскоп не активен, слушаем стрелки
        if (!this.isCalibrated || (this.tilt.x === 0 && this.tilt.y === 0)) {
            this.tilt.x = keys.ArrowRight ? 1 : keys.ArrowLeft ? -1 : 0;
            this.tilt.y = keys.ArrowDown ? 1 : keys.ArrowUp ? -1 : 0;
        }
    }

    generateLevel() {
        this.cats = [];
        this.yarns = [];

        const numCats = Math.floor(Math.random() * 2) + 3; // 3 или 4 кота
        const numYarns = numCats * 2; // По 2 клубка на кота



 //////////////////////////////////////////////////////////////////////////////////////
            //ДЩКУПОТМЦДУКЕПРТМЦЩКШЕОТПМДЦКШЩЕОРТМПЦЩКЕШРОТМЩКЕРОТМДКЩЕРМТ
 //////////////////////////////////////////////////////////////////////////////////////
        // 1. Генерируем котов в случайных местах БЕЗ НАЛОЖЕНИЙ
        const aspectRatio = window.innerWidth / window.innerHeight;

        for (let i = 0; i < numCats; i++) {
            let spawnX, spawnY, isTooClose;
            let attempts = 0;

            do {
                spawnX = 0.15 + Math.random() * 0.7;
                spawnY = 0.15 + Math.random() * 0.7;

                // Проверяем, не слишком ли близко к другим котам
                isTooClose = this.cats.some(cat => {
                    const dx = (spawnX - cat.x) * aspectRatio;
                    const dy = spawnY - cat.y;
                    // Радиус кота * 2 (чтобы они не пересекались) + отступ 0.1 для красоты
                    return Math.hypot(dx, dy) < (this.catRadius * 2 + 0.1);
                });

                attempts++;
            } while (isTooClose && attempts < 50);

            this.cats.push({
                id: `cat-${i}`,
                x: spawnX,
                y: spawnY,
                balls: 0
            });
        }
//////////////////////////////////////////////////////////////////////////////////////////////////
        //ЫШГПТЦДШГКЕПТМЦЩШКГЕРПТМЦЩШКГЕРТПМЦШКЕГРТМЦДШКГЕРТМДШГКЕРМТШКГЕРМТУДКШЕГРТМУДШКЕГРМТ
        /////////////////////////////////////////////////////////////////////////////////////////
        // 2. Генерируем клубки БЕЗ НАЛОЖЕНИЙ
        for (let i = 0; i < numYarns; i++) {
            let spawnX, spawnY, isTooClose;
            let attempts = 0;

            do {
                // Генерируем случайную точку
                spawnX = 0.1 + Math.random() * 0.8;
                spawnY = 0.1 + Math.random() * 0.8;

                // Проверяем, не слишком ли близко к КОТАМ
                const tooCloseToCat = this.cats.some(cat => {
                    const dx = (spawnX - cat.x) * aspectRatio;
                    const dy = spawnY - cat.y;
                    // Добавляем + 0.05, чтобы клубок не спавнился прямо на границе кота
                    return Math.hypot(dx, dy) < (this.yarnRadius + this.catRadius + 0.05);
                });

                // Проверяем, не слишком ли близко к ДРУГИМ КЛУБКАМ
                const tooCloseToYarn = this.yarns.some(yarn => {
                    const dx = (spawnX - yarn.x) * aspectRatio;
                    const dy = spawnY - yarn.y;
                    // Умножаем радиус на 2 (так как мы считаем от центра до центра) + 0.03 для зазора
                    return Math.hypot(dx, dy) < (this.yarnRadius * 2 + 0.03);
                });

                isTooClose = tooCloseToCat || tooCloseToYarn;
                attempts++;

                // Если попались 50 раз подряд (очень тесно), сдаемся и спавним как есть
            } while (isTooClose && attempts < 50);

            this.yarns.push({
                id: `yarn-${i}`,
                x: spawnX,
                y: spawnY,
                variant: Math.floor(Math.random() * 8),
                isCaught: false,
                vx: 0, // <--- ДОБАВЛЕНО: скорость по X
                vy: 0  // <--- ДОБАВЛЕНО: скорость по Y
            });
        }

        // Первичная отправка сцены в рендерер
        window.CatAnimation.setScene({
            visible: true,
            cats: this.cats,
            yarns: this.yarns
        });
    }

    // gameLoop() {
    //     if (!this.isPlaying) return;
    //
    //     let activeYarns = this.yarns.filter(y => !y.isCaught);
    //     const aspectRatio = window.innerWidth / window.innerHeight;
    //     const bounceFactor = 0.6; // Сила отскока (0 - нет отскока, 1 - идеальный отскок)
    //
    //     // 1. Применяем наклон + скорость отскока, и трение
    //     activeYarns.forEach(yarn => {
    //         // Трение (скорость отскока постепенно затухает)
    //         yarn.vx *= 0.85;
    //         yarn.vy *= 0.85;
    //
    //         // Итоговое движение: наклон от телефона + импульс отскока
    //         yarn.x += this.tilt.x * 0.015 + yarn.vx;
    //         yarn.y += this.tilt.y * 0.015 + yarn.vy;
    //     });
    //
    //     // 2. Отскок от стен экрана
    //     activeYarns.forEach(yarn => {
    //         if (yarn.x < 0.04) {
    //             yarn.x = 0.04;
    //             yarn.vx = Math.abs(yarn.vx) * bounceFactor + 0.005; // Отскок вправо
    //         }
    //         if (yarn.x > 0.96) {
    //             yarn.x = 0.96;
    //             yarn.vx = -Math.abs(yarn.vx) * bounceFactor - 0.005; // Отскок влево
    //         }
    //         if (yarn.y < 0.04) {
    //             yarn.y = 0.04;
    //             yarn.vy = Math.abs(yarn.vy) * bounceFactor + 0.005; // Отскок вниз
    //         }
    //         if (yarn.y > 0.96) {
    //             yarn.y = 0.96;
    //             yarn.vy = -Math.abs(yarn.vy) * bounceFactor - 0.005; // Отскок вверх
    //         }
    //     });
    //
    //     // 3. Отскок между клубками (эффект "ртути")
    //     for (let i = 0; i < activeYarns.length; i++) {
    //         for (let j = i + 1; j < activeYarns.length; j++) {
    //             const yA = activeYarns[i];
    //             const yB = activeYarns[j];
    //
    //             const dx = (yA.x - yB.x) * aspectRatio;
    //             const dy = yA.y - yB.y;
    //             const dist = Math.hypot(dx, dy);
    //             const minDist = this.yarnRadius * 2;
    //
    //             if (dist < minDist && dist > 0) {
    //                 const overlap = (minDist - dist) / 2;
    //                 const nx = dx / dist; // Нормаль столкновения
    //                 const ny = dy / dist;
    //
    //                 // Раздвигаем позиции
    //                 yA.x += (nx * overlap) / aspectRatio;
    //                 yA.y += ny * overlap;
    //                 yB.x -= (nx * overlap) / aspectRatio;
    //                 yB.y -= ny * overlap;
    //
    //                 // Добавляем импульс отскока (толкаем друг друга)
    //                 yA.vx += nx * 0.015;
    //                 yA.vy += ny * 0.015;
    //                 yB.vx -= nx * 0.015;
    //                 yB.vy -= ny * 0.015;
    //             }
    //         }
    //     }
    //
    //     // 4. Коллизия с котами
    //     activeYarns.forEach(yarn => {
    //         this.cats.forEach(cat => {
    //             const dx = (yarn.x - cat.x) * aspectRatio;
    //             const dy = yarn.y - cat.y;
    //             const dist = Math.hypot(dx, dy);
    //             const minDist = this.yarnRadius + this.catRadius;
    //
    //             if (dist < minDist) {
    //                 if (cat.balls < 2) {
    //                     // Кот голоден — забираем
    //                     yarn.isCaught = true;
    //                     cat.balls++;
    //
    //                     window.CatAnimation.playCatch({ catId: cat.id, x: yarn.x, y: yarn.y });
    //                     if (window.PrankBridge?.emit) window.PrankBridge.emit('action', { action: 'cat_caught', catId: cat.id });
    //                 } else {
    //                     // Кот сыт — ОТТАЛКИВАЕМ с отскоком
    //                     const angle = Math.atan2(dy, dx);
    //                     const nx = Math.cos(angle);
    //                     const ny = Math.sin(angle);
    //
    //                     // Возвращаем на границу
    //                     yarn.x = cat.x + (nx * minDist) / aspectRatio;
    //                     yarn.y = cat.y + ny * minDist;
    //
    //                     // Даем импульс отскока от кота
    //                     yarn.vx += nx * 0.02;
    //                     yarn.vy += ny * 0.02;
    //                 }
    //             }
    //         });
    //     });
    //
    //     // 5. Обновление сцены
    //     window.CatAnimation.setScene({
    //         visible: true,
    //         cats: this.cats,
    //         yarns: activeYarns
    //     });
    //
    //     // 6. Проверка победы
    //     if (activeYarns.length === 0) {
    //         this.triggerWin();
    //         return;
    //     }
    //
    //     this.rafId = requestAnimationFrame(this.boundFrame);
    // }

    gameLoop() {
        if (!this.isPlaying) return;

        let activeYarns = this.yarns.filter(y => !y.isCaught);
        const aspectRatio = window.innerWidth / window.innerHeight;

        // НАСТРОЙКИ ФИЗИКИ (изменены для плавности)
        const acceleration = 0.0012; // Было 0.003 (уменьшили в 2.5 раза)
        const friction = 0.92;       // Оставляем (плавное затухание)
        const bounceFactor = 0.5;    // Отскок от стен (было 0.6)

        // 1. ПРИМЕНЯЕМ СИЛУ
        activeYarns.forEach(yarn => {
            yarn.vx += this.tilt.x * acceleration;
            yarn.vy += this.tilt.y * acceleration;

            yarn.vx *= friction;
            yarn.vy *= friction;

            yarn.x += yarn.vx;
            yarn.y += yarn.vy;
        });

        // 2. Отскок от стен экрана
        activeYarns.forEach(yarn => {
            if (yarn.x < 0.04) { yarn.x = 0.04; yarn.vx = Math.abs(yarn.vx) * bounceFactor; }
            if (yarn.x > 0.96) { yarn.x = 0.96; yarn.vx = -Math.abs(yarn.vx) * bounceFactor; }
            if (yarn.y < 0.04) { yarn.y = 0.04; yarn.vy = Math.abs(yarn.vy) * bounceFactor; }
            if (yarn.y > 0.96) { yarn.y = 0.96; yarn.vy = -Math.abs(yarn.vy) * bounceFactor; }
        });

        // 3. Отскок между клубками
        for (let i = 0; i < activeYarns.length; i++) {
            for (let j = i + 1; j < activeYarns.length; j++) {
                const yA = activeYarns[i];
                const yB = activeYarns[j];

                const dx = (yA.x - yB.x) * aspectRatio;
                const dy = yA.y - yB.y;
                const dist = Math.hypot(dx, dy);
                const minDist = this.yarnRadius * 2;

                if (dist < minDist && dist > 0) {
                    const overlap = (minDist - dist) / 2;
                    const nx = dx / dist;
                    const ny = dy / dist;

                    yA.x += (nx * overlap) / aspectRatio;
                    yA.y += ny * overlap;
                    yB.x -= (nx * overlap) / aspectRatio;
                    yB.y -= ny * overlap;

                    // УМЕНЬШЕН ИМПУЛЬС ОТСКОКА МЕЖДУ КЛУБКАМИ (было 0.015)
                    yA.vx += nx * 0.004;
                    yA.vy += ny * 0.004;
                    yB.vx -= nx * 0.004;
                    yB.vy -= ny * 0.004;
                }
            }
        }

        // 4. Коллизия с котами
        activeYarns.forEach(yarn => {
            this.cats.forEach(cat => {
                const dx = (yarn.x - cat.x) * aspectRatio;
                const dy = yarn.y - cat.y;
                const dist = Math.hypot(dx, dy);
                const minDist = this.yarnRadius + this.catRadius;

                if (dist < minDist) {
                    if (cat.balls < 2) {
                        yarn.isCaught = true;
                        cat.balls++;

                        window.CatAnimation.playCatch({ catId: cat.id, x: yarn.x, y: yarn.y });
                        if (window.PrankBridge?.emit) window.PrankBridge.emit('action', { action: 'cat_caught', catId: cat.id });
                    } else {
                        const angle = Math.atan2(dy, dx);
                        const nx = Math.cos(angle);
                        const ny = Math.sin(angle);

                        yarn.x = cat.x + (nx * minDist) / aspectRatio;
                        yarn.y = cat.y + ny * minDist;

                        // УМЕНЬШЕН ИМПУЛЬС ОТСКОКА ОТ КОТА (было 0.025)
                        yarn.vx = nx * 0.008;
                        yarn.vy = ny * 0.008;
                    }
                }
            });
        });

        // 5. Обновление сцены
        window.CatAnimation.setScene({
            visible: true,
            cats: this.cats,
            yarns: activeYarns
        });

        // 6. Проверка победы
        if (activeYarns.length === 0) {
            this.triggerWin();
            return;
        }

        this.rafId = requestAnimationFrame(this.boundFrame);
    }

    triggerWin() {
        this.isPlaying = false;
        console.log("[GameEngine] Все клубки пойманы! Запуск танца...");

        // Запускаем танец (длительность берем из atlas.json или ставим 1600мс)
        window.CatAnimation.playDance({ durationMs: 1600 });

        // Ждем окончания танца
        const onDanceComplete = () => {
            window.removeEventListener('cat-animation:dance-complete', onDanceComplete);

            console.log("[GameEngine] Танец окончен. Отправляем game_won нативу.");
            if (window.PrankBridge?.emit) {
                window.PrankBridge.emit('action', { action: 'game_won' });
            }
        };
        window.addEventListener('cat-animation:dance-complete', onDanceComplete);
    }
}