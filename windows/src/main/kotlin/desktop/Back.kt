package com.unoki99.fangfang.desktop

/** Android's back gesture, on Windows: Esc and the mouse's back button go to the last BackHandler shown that's on */
object Back {
    class Handler(val enabled: () -> Boolean, val run: () -> Unit)
    private val list = ArrayList<Handler>()
    fun add(h: Handler) { synchronized(list) { list.add(h) } }
    fun remove(h: Handler) { synchronized(list) { list.remove(h) } }
    /** true: something went back */
    fun go(): Boolean {
        val h = synchronized(list) { list.lastOrNull { it.enabled() } } ?: return false
        h.run()
        return true
    }
}
