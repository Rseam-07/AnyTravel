package cn.anytravel.app

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PlannerFlowTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Before
    fun resetWelcome() {
        composeRule.activity
            .getSharedPreferences("anytravel", android.content.Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
    }

    @Test
    fun welcomeCanBeSkippedAndSuzhouPlanCanBeGenerated() {
        if (composeRule.onAllNodes(hasText("稍后设置")).fetchSemanticsNodes().isEmpty()) {
            composeRule.onNodeWithContentDescription("设置与数据渠道").performClick()
            composeRule.onNodeWithTag("settings-list").performScrollToNode(hasTestTag("restart-welcome"))
            composeRule.onNodeWithTag("restart-welcome").performClick()
        }
        composeRule.onNodeWithText("下一次旅行，你想前往哪里？").assertIsDisplayed()
        composeRule.onNodeWithText("稍后设置").performClick()

        composeRule.onNodeWithTag("draft-list").performScrollToNode(hasTestTag("generate-plan"))
        composeRule.onNodeWithTag("generate-plan").performClick()
        composeRule.waitUntil(timeoutMillis = 12_000) {
            composeRule.onAllNodes(hasText("跳过，交给 AnyTravel")).fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("跳过，交给 AnyTravel").performClick()
        composeRule.waitUntil(timeoutMillis = 12_000) {
            composeRule.onAllNodes(hasText("苏州 · 3天")).fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("苏州 · 3天").assertIsDisplayed()
        composeRule.onNodeWithText("日程").assertIsDisplayed()
        composeRule.onNodeWithText("住宿").assertIsDisplayed()
        composeRule.onNodeWithText("交通").assertIsDisplayed()
        composeRule.onNodeWithText("费用").assertIsDisplayed()
    }
}
