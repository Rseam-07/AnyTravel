package cn.anytravel.app.data

import cn.anytravel.app.model.CompletePlan

/** Replace the same trip in place and retain every other saved trip. */
internal fun mergeSavedPlan(plan: CompletePlan, existing: List<CompletePlan>): List<CompletePlan> =
    listOf(plan) + existing.filterNot { it.id == plan.id }
