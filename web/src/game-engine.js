export class GameEngine {
    constructor() {
        this.isPlaying = false;
        this.cats = [];
        this.yarns = [];

        // Данные гироскопа
        this.tilt = { x: 0, y: 0 };
        this.calibration = null; // Для запоминания начального угла телефона
        this.isCalibrated = false;

        // Константы для коллизий (в нормализованных координатах 0..1)
        this.yarnRadius = 0.06;
        this.catRadius = 0.12;

        // Коллизии между объектами считаем в «долях короткой стороны экрана»,
        // чтобы круг оставался кругом и на вытянутом экране 9:19,5.
        this.yarnBodyRadius = 0.06; // клубок ≈ 0,12 короткой стороны
        this.catBodyRadius = 0.17;  // котик ≈ 0,34 короткой стороны

        this.boundOrientation = this.handleOrientation.bind(this);
        this.boundFrame = this.gameLoop.bind(this);
        this.rafId = null;
    }

    start() {
        this.isPlaying = true;
        this.isCalibrated = false;
        this.generateLevel();

        window.addEventListener('deviceorientation', this.boundOrientation);
        this.rafId = requestAnimationFrame(this.boundFrame);

        console.log("[GameEngine] Игра запущена. Наклоняйте телефон (или используйте стрелки).");
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

        // 1. Генерируем котов в случайных местах (не у самых краев) и не друг на друге
        for (let i = 0; i < numCats; i++) {
            let spawn;
            let attempts = 0;
            do {
                spawn = { x: 0.15 + Math.random() * 0.7, y: 0.15 + Math.random() * 0.7 }; // 15–85% экрана
                attempts++;
            } while (
                this.cats.some(cat => this.distance(spawn, cat) < this.catBodyRadius * 2) &&
                attempts < 200
            );
            this.cats.push({ id: `cat-${i}`, x: spawn.x, y: spawn.y, balls: 0 });
        }

        // 2. Генерируем клубки
        for (let i = 0; i < numYarns; i++) {
            let spawnX, spawnY, isTooCloseToCat;
            let attempts = 0;

            // Клубки не появляются ни на котах, ни друг на друге
            do {
                spawnX = 0.1 + Math.random() * 0.8;
                spawnY = 0.1 + Math.random() * 0.8;
                const spawn = { x: spawnX, y: spawnY };
                isTooCloseToCat =
                    this.cats.some(cat =>
                        Math.hypot(spawnX - cat.x, spawnY - cat.y) < (this.yarnRadius + this.catRadius)
                    ) ||
                    this.yarns.some(yarn => this.distance(spawn, yarn) < this.yarnBodyRadius * 2);
                attempts++;
            } while (isTooCloseToCat && attempts < 200);

            this.yarns.push({
                id: `yarn-${i}`,
                x: spawnX,
                y: spawnY,
                variant: Math.floor(Math.random() * 8), // 8 вариантов клубков
                isCaught: false
            });
        }

        // Первичная отправка сцены в рендерер
        window.CatAnimation.setScene({
            visible: true,
            cats: this.cats,
            yarns: this.yarns
        });
    }

    gameLoop() {
        if (!this.isPlaying) return;

        let activeYarns = this.yarns.filter(y => !y.isCaught);

        // 1. Физика движения клубков
        activeYarns.forEach(yarn => {
            // Смещаем клубки с учетом наклона
            const dx = this.tilt.x * 0.012;
            const dy = this.tilt.y * 0.012;

            yarn.x += dx;
            yarn.y += dy;

            // Жестко ограничиваем координаты (чтобы не улетали за экран)
            yarn.x = Math.max(0.05, Math.min(0.95, yarn.x));
            yarn.y = Math.max(0.05, Math.min(0.95, yarn.y));
        });

        // 1б. Клубки сталкиваются друг с другом, а не слипаются
        this.separateYarns(activeYarns);

        // 2. Проверка коллизий
        activeYarns.forEach(yarn => {
            this.cats.forEach(cat => {
                if (cat.balls >= 2) return; // Кот уже сыт

                // Считаем расстояние между центрами
                const dist = Math.hypot(yarn.x - cat.x, yarn.y - cat.y);

                if (dist < (this.yarnRadius + this.catRadius)) {
                    // Коллизия!
                    yarn.isCaught = true;
                    cat.balls++;

                    // Вызываем эффект частиц
                    window.CatAnimation.playCatch({
                        catId: cat.id,
                        x: yarn.x,
                        y: yarn.y
                    });

                    // Отправляем нативу для вибрации
                    if (window.PrankBridge?.emit) {
                        window.PrankBridge.emit('action', { action: 'cat_caught', catId: cat.id });
                    }
                }
            });
        });

        // 3. Обновление сцены в рендерере
        window.CatAnimation.setScene({
            visible: true,
            cats: this.cats,
            yarns: activeYarns
        });

        // 4. Проверка победы
        if (activeYarns.length === 0) {
            this.triggerWin();
            return;
        }

        this.rafId = requestAnimationFrame(this.boundFrame);
    }

    /// Масштаб нормализованных осей к короткой стороне экрана.
    aspect() {
        const width = window.innerWidth || 1;
        const height = window.innerHeight || 1;
        const short = Math.min(width, height);
        return { x: width / short, y: height / short };
    }

    /// Расстояние между точками в долях короткой стороны экрана.
    distance(a, b) {
        const k = this.aspect();
        return Math.hypot((a.x - b.x) * k.x, (a.y - b.y) * k.y);
    }

    /// Расталкиваем пересекающиеся клубки поровну вдоль линии центров (несколько проходов —
    /// чтобы кучка в углу тоже разошлась). Края экрана остаются жёсткими.
    separateYarns(yarns) {
        const k = this.aspect();
        const minDistance = this.yarnBodyRadius * 2;
        for (let pass = 0; pass < 3; pass++) {
            for (let i = 0; i < yarns.length; i++) {
                for (let j = i + 1; j < yarns.length; j++) {
                    const a = yarns[i];
                    const b = yarns[j];
                    let dx = (b.x - a.x) * k.x;
                    let dy = (b.y - a.y) * k.y;
                    let dist = Math.hypot(dx, dy);
                    if (dist >= minDistance) continue;
                    if (dist < 1e-6) {
                        // Совпали точно — разводим в случайную сторону
                        const angle = Math.random() * Math.PI * 2;
                        dx = Math.cos(angle);
                        dy = Math.sin(angle);
                        dist = 1;
                    }
                    const push = (minDistance - Math.min(dist, minDistance)) / 2;
                    const nx = dx / dist;
                    const ny = dy / dist;
                    a.x -= (nx * push) / k.x;
                    a.y -= (ny * push) / k.y;
                    b.x += (nx * push) / k.x;
                    b.y += (ny * push) / k.y;
                    a.x = Math.max(0.05, Math.min(0.95, a.x));
                    a.y = Math.max(0.05, Math.min(0.95, a.y));
                    b.x = Math.max(0.05, Math.min(0.95, b.x));
                    b.y = Math.max(0.05, Math.min(0.95, b.y));
                }
            }
        }
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