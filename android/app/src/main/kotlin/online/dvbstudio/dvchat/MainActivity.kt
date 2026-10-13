package online.dvbstudio.dvchat
import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

import android.content.Context
import android.os.Bundle
import android.view.WindowManager

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // DVChat: запрет скриншотов и записи экрана, содержимое скрыто в списке недавних
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }


    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
    }


    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return provideEngine(getApplicationContext())
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // do nothing, because the engine was been configured in provideEngine
    }

    // Prevent Flutter engine gets destroyed on back button close.
    override fun createFlutterFragment(): FlutterFragment =
        super.createFlutterFragment().apply {
            arguments?.putBoolean("destroy_engine_with_fragment", false)
        }

    companion object {
        var engine: FlutterEngine? = null
        fun provideEngine(context: Context): FlutterEngine {
            val eng = engine ?: FlutterEngine(context, emptyArray(), true, false)
            engine = eng
            return eng
        }
    }
}
