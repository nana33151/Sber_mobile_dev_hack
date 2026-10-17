package com.example.prank

import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class DemoActivity : AppCompatActivity() {

    private lateinit var background: ImageView
    private lateinit var title: TextView
    private var currentScreen = "home"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = FrameLayout(this)

        // Фон: сюда потом пойдут реальные скрины банка
        background = ImageView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            scaleType = ImageView.ScaleType.CENTER_CROP
        }
        root.addView(background)

        // Заголовок поверх (для отладки; потом можно скрыть)
        title = TextView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                topMargin = 120
                leftMargin = 48
            }
            textSize = 22f
            setTextColor(Color.WHITE)
            setShadowLayer(4f, 0f, 2f, Color.BLACK)
        }
        root.addView(title)

        // Нижняя навигация
        val nav = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { gravity = Gravity.BOTTOM }
            setPadding(0, 0, 0, 80)
        }

        fun makeNavButton(label: String, screen: String): TextView =
            TextView(this).apply {
                text = label
                textSize = 16f
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                setBackgroundColor(Color.parseColor("#CC21A038"))
                setPadding(0, 40, 0, 40)
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                    marginStart = 12
                    marginEnd = 12
                }
                setOnClickListener { switchTo(screen) }
            }

        nav.addView(makeNavButton("Главная", "home"))
        nav.addView(makeNavButton("Оплата", "payment"))
        nav.addView(makeNavButton("Профиль", "profile"))
        root.addView(nav)

        setContentView(root)
        switchTo("home")
    }

    private fun switchTo(screen: String) {
        if (screen == currentScreen && background.drawable != null) {
            sendScreenBroadcast(screen)
            return
        }
        currentScreen = screen

        // ─── ВАРИАНТ 1: цветной плейсхолдер (работает без ресурсов) ───
        // Когда добавятся скрины — закомментируй этот блок и раскомментируй ВАРИАНТ 2.
        val color = when (screen) {
            "home"    -> Color.parseColor("#21A038")
            "payment" -> Color.parseColor("#F5F5F5")
            "profile" -> Color.parseColor("#E8EAF0")
            else      -> Color.GRAY
        }
        background.setImageDrawable(
            GradientDrawable().apply { setColor(color) }
        )

        // ─── ВАРИАНТ 2: реальные скрины банка ───
        // Раскомментируй, когда положишь PNG в android/app/src/main/res/drawable/:
        //   demo_screen_home.png, demo_screen_payment.png, demo_screen_profile.png
        //
        // val resId = when (screen) {
        //     "home"    -> R.drawable.demo_screen_home
        //     "payment" -> R.drawable.demo_screen_payment
        //     "profile" -> R.drawable.demo_screen_profile
        //     else      -> R.drawable.demo_screen_home
        // }
        // background.setImageResource(resId)

	title.text = when (screen) {
	    "home"    -> "Главная (игра: котики с клубками)"
	    "payment" -> "Оплата (prank: финальный танец котика)"
	    "profile" -> "Профиль (игра: один танцующий котик)"
	    else      -> screen
	}

        sendScreenBroadcast(screen)
    }

    private fun sendScreenBroadcast(screen: String) {
        sendBroadcast(
            Intent(PrankTriggerService.ACTION_SCREEN_CHANGED).apply {
                setPackage(packageName)
                putExtra(PrankTriggerService.EXTRA_SCREEN, screen)
            }
        )
    }
    override fun onResume() {
    super.onResume()
    sendScreenBroadcast(currentScreen)
}
}
