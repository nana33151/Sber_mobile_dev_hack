package com.example.prank

import org.json.JSONObject

data class Frame(val x: Int, val y: Int, val width: Int, val height: Int)

data class Sheet(
    val assetFile: String,
    val namedFrames: Map<String, Frame>,
    val indexedFrames: List<Frame>,
)

data class Atlas(
    val catStates: Sheet,
    val catDance: Sheet,
    val yarnVariants: Sheet,
) {
    companion object {
        fun parse(json: String): Atlas {
            val root = JSONObject(json)
            return Atlas(
                catStates = parseNamedSheet(root.getJSONObject("catStates")),
                catDance = parseArraySheet(root.getJSONObject("catDance")),
                yarnVariants = parseArraySheet(root.getJSONObject("yarnVariants")),
            )
        }

        private fun parseNamedSheet(node: JSONObject): Sheet {
            val frames = node.getJSONObject("frames")
            val named = buildMap {
                frames.keys().forEach { k -> put(k, parseFrame(frames.getJSONObject(k))) }
            }
            return Sheet(node.getString("image"), named, emptyList())
        }

        private fun parseArraySheet(node: JSONObject): Sheet {
            val arr = node.getJSONArray("frames")
            val list = (0 until arr.length()).map { parseFrame(arr.getJSONObject(it)) }
            return Sheet(node.getString("image"), emptyMap(), list)
        }

        private fun parseFrame(o: JSONObject) = Frame(
            x = o.getInt("x"),
            y = o.getInt("y"),
            width = o.getInt("width"),
            height = o.getInt("height"),
        )
    }
}
