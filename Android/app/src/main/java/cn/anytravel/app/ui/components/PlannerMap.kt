package cn.anytravel.app.ui.components

import android.content.ComponentCallbacks2
import android.content.res.Configuration
import android.graphics.Color as AndroidColor
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import cn.anytravel.app.BuildConfig
import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.Coordinate
import cn.anytravel.app.ui.PlanTab
import cn.anytravel.app.ui.MapAppearance
import cn.anytravel.app.ui.theme.AnyTravelMotion
import cn.anytravel.app.ui.theme.DayRouteColors
import org.maplibre.android.annotations.Annotation
import org.maplibre.android.annotations.MarkerOptions
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapLibreMapOptions
import org.maplibre.android.maps.MapView
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.Property.LINE_CAP_ROUND
import org.maplibre.android.style.layers.Property.LINE_JOIN_ROUND
import org.maplibre.android.style.layers.PropertyFactory.lineCap
import org.maplibre.android.style.layers.PropertyFactory.lineColor
import org.maplibre.android.style.layers.PropertyFactory.lineDasharray
import org.maplibre.android.style.layers.PropertyFactory.lineJoin
import org.maplibre.android.style.layers.PropertyFactory.lineOpacity
import org.maplibre.android.style.layers.PropertyFactory.lineWidth
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point
import kotlin.math.min

@Composable
fun PlannerMap(
    plan: CompletePlan?,
    draftCenter: Coordinate?,
    selectedDay: Int,
    selectedTab: PlanTab,
    autoCamera: Boolean,
    cameraRequestToken: Int,
    northRequestToken: Int,
    mapAppearance: MapAppearance,
    focusedPlaceID: String?,
    onUserGesture: () -> Unit,
    onMapLongPress: (Coordinate) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val darkMode = isSystemInDarkTheme()
    val routeDuration = AnyTravelMotion.routeDuration()
    val holder = remember { MapHolder() }
    val mapView = remember {
        val deviceDensity = context.resources.displayMetrics.density
        // Android 12 flagships with very dense/4K panels can otherwise allocate
        // a disproportionately expensive map texture under the Compose sheet.
        // Capping only the map pixel ratio keeps text crisp while reducing GL
        // memory and tile decode pressure; the rest of the UI stays native dpi.
        val mapPixelRatio = if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.S_V2) {
            min(deviceDensity, 2.5f)
        } else {
            deviceDensity
        }
        val options = MapLibreMapOptions.createFromAttributes(context)
            // A TextureView avoids several SurfaceView/GL teardown crashes seen
            // on Android 12 OEM builds and composes cleanly under the sheet.
            .textureMode(Build.VERSION.SDK_INT <= Build.VERSION_CODES.S_V2)
            .translucentTextureSurface(false)
            .pixelRatio(mapPixelRatio)
            .asyncRendererCleanup(true)
            .fastPFOREnabled(true)
            .localIdeographFontFamily("sans-serif")
            .setPrefetchesTiles(true)
            .setPrefetchZoomDelta(1)
        MapView(context, options).also { view ->
            view.contentDescription = "旅行路线地图"
            view.onCreate(null)
            view.setMaximumFps(60)
            view.getMapAsync(holder::attach)
        }
    }

    holder.update(
        MapRenderRequest(
            plan = plan,
            draftCenter = draftCenter,
            selectedDay = selectedDay,
            selectedTab = selectedTab,
            autoCamera = autoCamera,
            focusedPlaceID = focusedPlaceID,
            styleURL = when (mapAppearance) {
                MapAppearance.SYSTEM -> if (darkMode) BuildConfig.MAP_DARK_STYLE_URL else BuildConfig.MAP_STYLE_URL
                MapAppearance.STREET -> BuildConfig.MAP_STYLE_URL
                MapAppearance.QUIET -> BuildConfig.MAP_LIGHT_STYLE_URL
                MapAppearance.NIGHT -> BuildConfig.MAP_DARK_STYLE_URL
            },
            routeDuration = routeDuration,
            cameraRequestToken = cameraRequestToken,
            northRequestToken = northRequestToken,
            onUserGesture = onUserGesture,
            onMapLongPress = onMapLongPress
        )
    )

    DisposableEffect(lifecycle, mapView) {
        val controller = MapViewLifecycleController(mapView)
        val observer = LifecycleEventObserver { _, event -> controller.handle(event) }
        val application = context.applicationContext
        val memoryCallbacks = object : ComponentCallbacks2 {
            override fun onConfigurationChanged(newConfig: Configuration) = Unit
            override fun onLowMemory() = mapView.notifyLowMemory()
            override fun onTrimMemory(level: Int) {
                if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) mapView.notifyLowMemory()
            }
        }
        lifecycle.addObserver(observer)
        application.registerComponentCallbacks(memoryCallbacks)
        controller.sync(lifecycle.currentState)
        onDispose {
            lifecycle.removeObserver(observer)
            application.unregisterComponentCallbacks(memoryCallbacks)
            holder.detach()
            controller.dispose()
        }
    }

    Box(modifier = modifier) {
        AndroidView(factory = { mapView }, modifier = Modifier.fillMaxSize())
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(
                            Color.Black.copy(alpha = if (darkMode) 0.26f else 0.16f),
                            Color.Transparent,
                            Color.Transparent
                        ),
                        endY = 520f
                    )
                )
        )
    }
}

private data class MapRenderRequest(
    val plan: CompletePlan?,
    val draftCenter: Coordinate?,
    val selectedDay: Int,
    val selectedTab: PlanTab,
    val autoCamera: Boolean,
    val focusedPlaceID: String?,
    val styleURL: String,
    val routeDuration: Int,
    val cameraRequestToken: Int,
    val northRequestToken: Int,
    val onUserGesture: () -> Unit,
    val onMapLongPress: (Coordinate) -> Unit
)

private class MapHolder {
    private companion object {
        const val ROUTE_SOURCE_ID = "anytravel-route-source"
        const val ROUTE_LAYER_ID = "anytravel-route-layer"
        const val FALLBACK_SOURCE_ID = "anytravel-route-fallback-source"
        const val FALLBACK_LAYER_ID = "anytravel-route-fallback-layer"
    }

    private var map: MapLibreMap? = null
    private var latestRequest: MapRenderRequest? = null
    private var requestedStyleURL: String? = null
    private var loadedStyleURL: String? = null
    private var styleReady = false
    private var geometryKey: String? = null
    private var cameraKey: String? = null
    private var handledNorthRequestToken = 0
    private val renderedAnnotations = mutableListOf<Annotation>()

    fun attach(map: MapLibreMap) {
        this.map = map
        map.uiSettings.apply {
            isRotateGesturesEnabled = true
            isTiltGesturesEnabled = false
            setCompassMargins(0, 128, 24, 0)
            setLogoMargins(20, 0, 0, 28)
            setAttributionMargins(0, 0, 20, 28)
        }
        map.addOnCameraMoveStartedListener { reason ->
            if (reason == MapLibreMap.OnCameraMoveStartedListener.REASON_API_GESTURE) {
                cameraKey = null
                latestRequest?.onUserGesture?.invoke()
            }
        }
        map.addOnMapLongClickListener { point ->
            latestRequest?.onMapLongPress?.invoke(Coordinate(point.latitude, point.longitude))
            true
        }
        latestRequest?.let(::update)
    }

    fun detach() {
        map?.cancelTransitions()
        map = null
        latestRequest = null
        renderedAnnotations.clear()
        geometryKey = null
        cameraKey = null
        styleReady = false
    }

    fun update(request: MapRenderRequest) {
        latestRequest = request
        val currentMap = map ?: return
        if (loadedStyleURL != request.styleURL) {
            loadStyle(currentMap, request.styleURL)
            return
        }
        render(currentMap, request)
    }

    private fun loadStyle(currentMap: MapLibreMap, styleURL: String) {
        if (requestedStyleURL == styleURL && !styleReady) return
        requestedStyleURL = styleURL
        styleReady = false
        currentMap.cancelTransitions()
        currentMap.setStyle(styleURL) {
            if (requestedStyleURL != styleURL || map !== currentMap) return@setStyle
            loadedStyleURL = styleURL
            styleReady = true
            renderedAnnotations.clear()
            geometryKey = null
            cameraKey = null
            latestRequest?.let { render(currentMap, it) }
        }
    }

    private fun render(currentMap: MapLibreMap, request: MapRenderRequest) {
        if (!styleReady) return
        renderGeometry(currentMap, request)
        renderCamera(currentMap, request)
    }

    private fun renderGeometry(currentMap: MapLibreMap, request: MapRenderRequest) {
        val nextKey = geometryFingerprint(request)
        if (geometryKey == nextKey) return

        currentMap.cancelTransitions()
        if (renderedAnnotations.isNotEmpty()) {
            runCatching { currentMap.removeAnnotations(renderedAnnotations.toList()) }
            renderedAnnotations.clear()
        }

        request.plan?.let { plan ->
            val visibleDays = plan.days.getOrNull(request.selectedDay)?.let(::listOf).orEmpty()
            val routeFeatures = visibleDays.flatMap { day ->
                val routed = plan.routeSegments.filter { it.dayIndex == day.index }
                routed.mapNotNull { segment ->
                    val points = segment.coordinates.map { Point.fromLngLat(it.longitude, it.latitude) }
                    points.takeIf { it.size >= 2 }?.let { Feature.fromGeometry(LineString.fromLngLats(it)) }
                }
            }
            val routedPairs = plan.routeSegments
                .asSequence()
                .filter { it.dayIndex == request.selectedDay }
                .mapTo(mutableSetOf()) { it.fromPlaceID to it.toPlaceID }
            val fallbackFeatures = visibleDays.flatMap { day ->
                day.stops.zipWithNext()
                    .filterNot { (from, to) -> (from.id to to.id) in routedPairs }
                    .map { (from, to) ->
                        Feature.fromGeometry(
                            LineString.fromLngLats(
                                listOf(
                                    Point.fromLngLat(from.coordinate.longitude, from.coordinate.latitude),
                                    Point.fromLngLat(to.coordinate.longitude, to.coordinate.latitude)
                                )
                            )
                        )
                    }
            }
            updateRouteLayers(
                currentMap = currentMap,
                color = DayRouteColors[request.selectedDay % DayRouteColors.size].toArgb(),
                routeFeatures = routeFeatures,
                fallbackFeatures = fallbackFeatures
            )

            val markers = buildList {
                visibleDays.flatMap { day ->
                    day.stops.mapIndexed { stopIndex, stop -> day to (stopIndex to stop) }
                }.distinctBy { (_, indexedStop) -> indexedStop.second.id }.forEach { (day, indexedStop) ->
                    val (stopIndex, stop) = indexedStop
                    add(
                        MarkerOptions()
                            .position(LatLng(stop.coordinate.latitude, stop.coordinate.longitude))
                            .title("第${day.index + 1}天 · ${stopIndex + 1}. ${stop.name}")
                            .snippet(stop.introduction)
                    )
                }
                plan.selectedAccommodation?.let { hotel ->
                    add(
                        MarkerOptions()
                            .position(LatLng(hotel.coordinate.latitude, hotel.coordinate.longitude))
                            .title("住处 · ${hotel.name}")
                            .snippet(hotel.recommendationReasons.joinToString(" · "))
                    )
                }
                plan.selectedTransport?.arrivalAccessPoint?.let { hub ->
                    add(
                        MarkerOptions()
                            .position(LatLng(hub.coordinate.latitude, hub.coordinate.longitude))
                            .title("抵达 · ${hub.name}")
                            .snippet("与已选住处的接驳距离会参与交通排序")
                    )
                }
            }
            if (markers.isNotEmpty()) renderedAnnotations += currentMap.addMarkers(markers)
        } ?: updateRouteLayers(
            currentMap = currentMap,
            color = DayRouteColors.first().toArgb(),
            routeFeatures = emptyList(),
            fallbackFeatures = emptyList()
        )
        geometryKey = nextKey
    }

    private fun updateRouteLayers(
        currentMap: MapLibreMap,
        color: Int,
        routeFeatures: List<Feature>,
        fallbackFeatures: List<Feature>
    ) {
        val style = currentMap.style ?: return
        val routeSource = style.getSourceAs<GeoJsonSource>(ROUTE_SOURCE_ID)
            ?: GeoJsonSource(ROUTE_SOURCE_ID).also(style::addSource)
        val fallbackSource = style.getSourceAs<GeoJsonSource>(FALLBACK_SOURCE_ID)
            ?: GeoJsonSource(FALLBACK_SOURCE_ID).also(style::addSource)
        val routeLayer = style.getLayerAs<LineLayer>(ROUTE_LAYER_ID) ?: run {
            val layer = LineLayer(ROUTE_LAYER_ID, ROUTE_SOURCE_ID).withProperties(
                lineColor(color),
                lineWidth(5.5f),
                lineOpacity(0.96f),
                lineCap(LINE_CAP_ROUND),
                lineJoin(LINE_JOIN_ROUND)
            )
            style.addLayer(
                layer
            )
            layer
        }
        val fallbackLayer = style.getLayerAs<LineLayer>(FALLBACK_LAYER_ID) ?: run {
            val layer = LineLayer(FALLBACK_LAYER_ID, FALLBACK_SOURCE_ID).withProperties(
                lineColor(color),
                lineWidth(3.5f),
                lineOpacity(0.38f),
                lineDasharray(arrayOf(1.2f, 1.6f)),
                lineCap(LINE_CAP_ROUND),
                lineJoin(LINE_JOIN_ROUND)
            )
            style.addLayerBelow(
                layer,
                ROUTE_LAYER_ID
            )
            layer
        }
        routeLayer.setProperties(lineColor(color))
        fallbackLayer.setProperties(lineColor(color))
        // Updating one GeoJSON source is substantially cheaper than allocating
        // and deleting a native annotation object for every route segment.
        routeSource.setGeoJson(FeatureCollection.fromFeatures(routeFeatures))
        fallbackSource.setGeoJson(FeatureCollection.fromFeatures(fallbackFeatures))
    }

    private fun renderCamera(currentMap: MapLibreMap, request: MapRenderRequest) {
        if (request.northRequestToken != handledNorthRequestToken) {
            currentMap.cancelTransitions()
            val north = CameraUpdateFactory.bearingTo(0.0)
            if (request.routeDuration == 0) currentMap.moveCamera(north)
            else currentMap.animateCamera(north, request.routeDuration)
            handledNorthRequestToken = request.northRequestToken
            return
        }
        if (!request.autoCamera) {
            // Clearing this key makes “回到当前路线” a real action after a
            // manual pan instead of being discarded as an already-seen request.
            cameraKey = null
            return
        }

        val nextKey = cameraFingerprint(request)
        if (cameraKey == nextKey) return
        val plan = request.plan
        val update = if (plan == null) {
            CameraUpdateFactory.newCameraPosition(
                CameraPosition.Builder()
                    .target(request.draftCenter?.let { LatLng(it.latitude, it.longitude) } ?: LatLng(34.2, 108.9))
                    .zoom(if (request.draftCenter == null) 4.2 else 10.5)
                    .build()
            )
        } else {
            val points = cameraPoints(plan, request.selectedDay, request.selectedTab, request.focusedPlaceID)
            cameraUpdateFor(currentMap, plan, points, request.selectedTab, request.focusedPlaceID)
        }
        currentMap.cancelTransitions()
        if (request.routeDuration == 0) currentMap.moveCamera(update)
        else currentMap.animateCamera(update, request.routeDuration)
        cameraKey = nextKey
    }

    private fun cameraUpdateFor(
        currentMap: MapLibreMap,
        plan: CompletePlan,
        points: List<LatLng>,
        tab: PlanTab,
        focusedPlaceID: String?
    ) = when {
        points.size > 1 && focusedPlaceID == null -> {
            val bounds = LatLngBounds.Builder().includes(points).build()
            val padding = when (tab) {
                PlanTab.STAYS -> intArrayOf(72, 180, 72, 430)
                PlanTab.TRANSPORT -> intArrayOf(92, 190, 92, 410)
                else -> intArrayOf(72, 170, 72, 390)
            }
            val fitted = currentMap.getCameraForLatLngBounds(bounds, padding)
            fitted?.let(CameraUpdateFactory::newCameraPosition)
                ?: CameraUpdateFactory.newLatLngBounds(bounds, padding[0])
        }
        else -> {
            val center = points.firstOrNull()
                ?: LatLng(plan.destinationCenter.latitude, plan.destinationCenter.longitude)
            val zoom = when {
                tab == PlanTab.TRANSPORT && plan.selectedTransport?.arrivalAccessPoint != null -> 10.8
                tab == PlanTab.STAYS -> 12.2
                focusedPlaceID != null -> 15.2
                else -> 13.5
            }
            CameraUpdateFactory.newCameraPosition(CameraPosition.Builder().target(center).zoom(zoom).build())
        }
    }

    private fun cameraPoints(
        plan: CompletePlan,
        selectedDay: Int,
        tab: PlanTab,
        focusedPlaceID: String?
    ): List<LatLng> {
        plan.days.flatMap { it.stops }.firstOrNull { it.id == focusedPlaceID }?.let {
            return listOf(LatLng(it.coordinate.latitude, it.coordinate.longitude))
        }
        return when (tab) {
            PlanTab.DAYS -> plan.days.getOrNull(selectedDay)?.stops.orEmpty().map {
                LatLng(it.coordinate.latitude, it.coordinate.longitude)
            }
            PlanTab.STAYS -> buildList {
                plan.accommodations.take(30).forEach { add(LatLng(it.coordinate.latitude, it.coordinate.longitude)) }
                plan.days.flatMap { it.stops }.forEach { add(LatLng(it.coordinate.latitude, it.coordinate.longitude)) }
            }
            PlanTab.TRANSPORT -> buildList {
                plan.selectedTransport?.arrivalAccessPoint?.coordinate?.let { add(LatLng(it.latitude, it.longitude)) }
                plan.selectedAccommodation?.coordinate?.let { add(LatLng(it.latitude, it.longitude)) }
            }
            PlanTab.COSTS -> plan.days.flatMap { it.stops }.map {
                LatLng(it.coordinate.latitude, it.coordinate.longitude)
            }
        }
    }

    private fun geometryFingerprint(request: MapRenderRequest): String = buildString {
        val plan = request.plan
        append(plan?.id ?: "draft")
        append('|').append(request.selectedDay)
        plan?.days?.getOrNull(request.selectedDay)?.let { day ->
            append('|').append(day.index)
            day.stops.forEach { stop ->
                append(':').append(stop.id)
                    .append('@').append(stop.coordinate.latitude)
                    .append(',').append(stop.coordinate.longitude)
            }
        }
        plan?.routeSegments?.asSequence()
            ?.filter { it.dayIndex == request.selectedDay }
            ?.forEach { segment ->
                append("|r:").append(segment.id).append('#').append(segment.coordinates.size)
                segment.coordinates.firstOrNull()?.let { append('@').append(it.latitude).append(',').append(it.longitude) }
                segment.coordinates.lastOrNull()?.let { append('>').append(it.latitude).append(',').append(it.longitude) }
            }
        append("|rf:").append(plan?.failedRouteSegmentCount ?: 0)
        plan?.selectedAccommodation?.let { append("|h:").append(it.id) }
        plan?.selectedTransport?.arrivalAccessPoint?.let {
            append("|t:").append(it.name).append('@').append(it.coordinate.latitude).append(',').append(it.coordinate.longitude)
        }
    }

    private fun cameraFingerprint(request: MapRenderRequest): String = buildString {
        append(geometryFingerprint(request))
        append('|').append(request.selectedTab.name)
        append('|').append(request.focusedPlaceID)
        append('|').append(request.draftCenter?.latitude).append(',').append(request.draftCenter?.longitude)
        append('|').append(request.cameraRequestToken)
    }
}

private class MapViewLifecycleController(private val mapView: MapView) {
    private var started = false
    private var resumed = false
    private var destroyed = false

    fun sync(state: Lifecycle.State) {
        if (destroyed || state == Lifecycle.State.DESTROYED) return
        if (state.isAtLeast(Lifecycle.State.STARTED)) start()
        if (state.isAtLeast(Lifecycle.State.RESUMED)) resume()
    }

    fun handle(event: Lifecycle.Event) {
        when (event) {
            Lifecycle.Event.ON_START -> start()
            Lifecycle.Event.ON_RESUME -> resume()
            Lifecycle.Event.ON_PAUSE -> pause()
            Lifecycle.Event.ON_STOP -> stop()
            Lifecycle.Event.ON_DESTROY -> dispose()
            else -> Unit
        }
    }

    private fun start() {
        if (!destroyed && !started) {
            mapView.onStart()
            started = true
        }
    }

    private fun resume() {
        if (!destroyed && !resumed) {
            if (!started) start()
            mapView.onResume()
            resumed = true
        }
    }

    private fun pause() {
        if (!destroyed && resumed) {
            mapView.onPause()
            resumed = false
        }
    }

    private fun stop() {
        if (!destroyed && started) {
            pause()
            mapView.onStop()
            started = false
        }
    }

    fun dispose() {
        if (destroyed) return
        stop()
        mapView.onDestroy()
        destroyed = true
    }
}

private fun MapView.notifyLowMemory() {
    post { if (!isDestroyed) onLowMemory() }
}

private fun Color.toArgb(): Int = AndroidColor.argb(
    (alpha * 255).toInt(),
    (red * 255).toInt(),
    (green * 255).toInt(),
    (blue * 255).toInt()
)
