package cn.anytravel.app.ui.components

import android.graphics.Color as AndroidColor
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import cn.anytravel.app.BuildConfig
import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.Coordinate
import cn.anytravel.app.ui.PlanTab
import cn.anytravel.app.ui.theme.AnyTravelMotion
import cn.anytravel.app.ui.theme.DayRouteColors
import org.maplibre.android.annotations.MarkerOptions
import org.maplibre.android.annotations.PolylineOptions
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView

@Composable
fun PlannerMap(
    plan: CompletePlan?,
    draftCenter: Coordinate?,
    selectedDay: Int,
    selectedTab: PlanTab,
    autoCamera: Boolean,
    focusedPlaceID: String?,
    onUserGesture: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val routeDuration = AnyTravelMotion.routeDuration()
    val holder = remember { MapHolder(onUserGesture) }
    val mapView = remember {
        MapView(context).also { view ->
            view.contentDescription = "旅行路线地图"
            view.onCreate(null)
            view.getMapAsync { map ->
                holder.map = map
                map.uiSettings.apply {
                    isRotateGesturesEnabled = true
                    isTiltGesturesEnabled = false
                    setCompassMargins(0, 128, 24, 0)
                    setLogoMargins(20, 0, 0, 28)
                    setAttributionMargins(0, 0, 20, 28)
                }
                map.addOnCameraMoveStartedListener { reason ->
                    if (reason == MapLibreMap.OnCameraMoveStartedListener.REASON_API_GESTURE) {
                        holder.onUserGesture()
                    }
                }
                map.setStyle(BuildConfig.MAP_STYLE_URL) {
                    holder.styleReady = true
                    holder.render(plan, draftCenter, selectedDay, selectedTab, autoCamera, focusedPlaceID, routeDuration)
                }
            }
        }
    }

    DisposableEffect(lifecycle, mapView) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> mapView.onStart()
                Lifecycle.Event.ON_RESUME -> mapView.onResume()
                Lifecycle.Event.ON_PAUSE -> mapView.onPause()
                Lifecycle.Event.ON_STOP -> mapView.onStop()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            mapView.onDestroy()
        }
    }

    Box(modifier = modifier) {
        AndroidView(
            factory = { mapView },
            update = {
                holder.onUserGesture = onUserGesture
                holder.render(plan, draftCenter, selectedDay, selectedTab, autoCamera, focusedPlaceID, routeDuration)
            },
            modifier = Modifier.fillMaxSize()
        )
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Black.copy(alpha = 0.16f), Color.Transparent, Color.Transparent),
                        endY = 520f
                    )
                )
        )
    }
}

private class MapHolder(var onUserGesture: () -> Unit) {
    var map: MapLibreMap? = null
    var styleReady = false
    private var renderedKey: String? = null
    private var cameraKey: String? = null

    fun render(
        plan: CompletePlan?,
        draftCenter: Coordinate?,
        selectedDay: Int,
        selectedTab: PlanTab,
        autoCamera: Boolean,
        focusedPlaceID: String?,
        duration: Int
    ) {
        val currentMap = map ?: return
        if (!styleReady) return
        val renderKey = listOf(
            plan?.id,
            plan?.selectedAccommodationId,
            plan?.selectedTransportId,
            draftCenter?.latitude,
            draftCenter?.longitude,
            selectedDay,
            selectedTab,
            focusedPlaceID
        ).joinToString("-")
        if (renderedKey != renderKey) {
            currentMap.clear()
            if (plan == null) {
                currentMap.cameraPosition = CameraPosition.Builder()
                    .target(
                        draftCenter?.let { LatLng(it.latitude, it.longitude) }
                            ?: LatLng(34.2, 108.9)
                    )
                    .zoom(if (draftCenter == null) 4.2 else 10.5)
                    .build()
            } else {
                plan.days.forEach { day ->
                    val coordinates = day.stops.map { LatLng(it.coordinate.latitude, it.coordinate.longitude) }
                    if (coordinates.size > 1) {
                        val color = DayRouteColors[day.index % DayRouteColors.size]
                        currentMap.addPolyline(
                            PolylineOptions()
                                .addAll(coordinates)
                                .color(color.toArgb())
                                .width(if (day.index == selectedDay) 7f else 4f)
                                .alpha(if (day.index == selectedDay) 0.96f else 0.55f)
                        )
                    }
                    day.stops.forEachIndexed { stopIndex, stop ->
                        currentMap.addMarker(
                            MarkerOptions()
                                .position(LatLng(stop.coordinate.latitude, stop.coordinate.longitude))
                                .title("第${day.index + 1}天 · ${stopIndex + 1}. ${stop.name}")
                                .snippet(stop.introduction)
                        )
                    }
                }
                plan.selectedAccommodation?.let { hotel ->
                    currentMap.addMarker(
                        MarkerOptions()
                            .position(LatLng(hotel.coordinate.latitude, hotel.coordinate.longitude))
                            .title("住处 · ${hotel.name}")
                            .snippet(hotel.recommendationReasons.joinToString(" · "))
                    )
                }
                plan.selectedTransport?.arrivalAccessPoint?.let { hub ->
                    currentMap.addMarker(
                        MarkerOptions()
                            .position(LatLng(hub.coordinate.latitude, hub.coordinate.longitude))
                            .title("抵达 · ${hub.name}")
                            .snippet("与已选住处的接驳距离会参与交通排序")
                    )
                }
            }
            renderedKey = renderKey
        }

        val requestedCameraKey = "$renderKey-$autoCamera"
        if (plan != null && autoCamera && cameraKey != requestedCameraKey) {
            val points = cameraPoints(plan, selectedDay, selectedTab, focusedPlaceID)
            val center = if (points.isEmpty()) {
                LatLng(plan.destinationCenter.latitude, plan.destinationCenter.longitude)
            } else {
                LatLng(points.map { it.latitude }.average(), points.map { it.longitude }.average())
            }
            val zoom = when {
                selectedTab == PlanTab.TRANSPORT && plan.selectedTransport?.arrivalAccessPoint != null -> 10.8
                selectedTab == PlanTab.STAYS -> 12.2
                focusedPlaceID != null -> 15.2
                points.size <= 2 -> 13.5
                else -> 12.5
            }
            val update = CameraUpdateFactory.newCameraPosition(
                CameraPosition.Builder().target(center).zoom(zoom).build()
            )
            if (duration == 0) currentMap.moveCamera(update) else currentMap.animateCamera(update, duration)
            cameraKey = requestedCameraKey
        }
    }

    private fun cameraPoints(plan: CompletePlan, selectedDay: Int, tab: PlanTab, focusedPlaceID: String?): List<LatLng> {
        plan.days.flatMap { it.stops }.firstOrNull { it.id == focusedPlaceID }?.let {
            return listOf(LatLng(it.coordinate.latitude, it.coordinate.longitude))
        }
        return when (tab) {
        PlanTab.DAYS -> plan.days.getOrNull(selectedDay)?.stops.orEmpty().map {
            LatLng(it.coordinate.latitude, it.coordinate.longitude)
        }
        PlanTab.STAYS -> buildList {
            plan.accommodations.forEach { add(LatLng(it.coordinate.latitude, it.coordinate.longitude)) }
            plan.days.flatMap { it.stops }.forEach { add(LatLng(it.coordinate.latitude, it.coordinate.longitude)) }
        }
        PlanTab.TRANSPORT -> buildList {
            plan.selectedTransport?.arrivalAccessPoint?.coordinate?.let { add(LatLng(it.latitude, it.longitude)) }
            plan.selectedAccommodation?.coordinate?.let { add(LatLng(it.latitude, it.longitude)) }
        }
        PlanTab.COSTS -> plan.days.flatMap { it.stops }.map { LatLng(it.coordinate.latitude, it.coordinate.longitude) }
        }
    }
}

private fun Color.toArgb(): Int = AndroidColor.argb(
    (alpha * 255).toInt(),
    (red * 255).toInt(),
    (green * 255).toInt(),
    (blue * 255).toInt()
)
