package cn.anytravel.app.data

import cn.anytravel.app.BuildConfig
import cn.anytravel.app.model.TripDraft
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

class TravelAssistantClientTest {
    private val client = TravelAssistantClient()

    @Test
    fun validatesAndClampsModelActionsBeforeTheyReachTheMap() {
        val result = client.validate(
            TravelAssistantInterpretation(
                reply = "  已经替你放慢脚步。  ",
                actions = listOf(
                    TravelAssistantAction("set_day_count", "99"),
                    TravelAssistantAction("set_budget", "100"),
                    TravelAssistantAction("set_skip_transport", "TRUE"),
                    TravelAssistantAction("focus_place", " 苏州博物馆 "),
                    TravelAssistantAction("remove_place", "不存在的地点"),
                    TravelAssistantAction("unsafe_action", "anything")
                )
            ),
            places = listOf(TravelAssistantPlaceContext("苏州博物馆", 0, "culture"))
        )

        assertEquals("已经替你放慢脚步。", result.reply)
        assertEquals("7", result.actions.first { it.type == "set_day_count" }.value)
        assertEquals("1000", result.actions.first { it.type == "set_budget" }.value)
        assertEquals("true", result.actions.first { it.type == "set_skip_transport" }.value)
        assertEquals("苏州博物馆", result.actions.first { it.type == "focus_place" }.value)
        assertFalse(result.actions.any { it.type == "remove_place" || it.type == "unsafe_action" })
    }

    @Test
    fun liveManagedAssistantUnderstandsAFreeFormTripRequest() = runBlocking {
        assumeTrue(System.getenv("ANYTRAVEL_RUN_LIVE_TESTS") == "1")
        assumeTrue(BuildConfig.ZAI_API_KEY.isNotBlank())

        val result = client.interpret(
            input = "我从上海出发去苏州玩三天，两个人，想轻松看看园林，请直接安排。",
            context = TravelAssistantContext.from(TripDraft(), null, 0),
            configuration = AssistantConfiguration(mode = AssistantProviderMode.MANAGED),
            managedServiceURL = ""
        )

        assertTrue(result.actions.any { it.type == "set_destination" && "苏州" in it.value })
        assertTrue(result.actions.any { it.type == "set_day_count" && it.value == "3" })
        assertTrue(result.actions.any { it.type == "generate_plan" && it.value == "true" })
    }
}
