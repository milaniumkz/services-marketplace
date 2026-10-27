import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'device_location.dart';
import 'l10n.dart';

LatLng? mapPoint(dynamic value) {
  if (value is! Map) return null;
  final lat = value['latitude'], lon = value['longitude'];
  return lat is num &&
          lon is num &&
          lat.isFinite &&
          lon.isFinite &&
          lat.abs() <= 90 &&
          lon.abs() <= 180
      ? LatLng(lat.toDouble(), lon.toDouble())
      : null;
}

Json pointJson(LatLng point) =>
    {'latitude': point.latitude, 'longitude': point.longitude};

/// The device point is local UI state, never an account update or public marker.
class OsmMap extends StatefulWidget {
  final LatLng? initialCenter, selected;
  final List<Marker> markers;
  final ValueChanged<LatLng>? onSelected, onLocated;
  final Future<Json?> Function()? locate;
  final bool autoLocate;
  final TileProvider? tileProvider;
  const OsmMap(
      {super.key,
      this.initialCenter,
      this.selected,
      this.markers = const [],
      this.onSelected,
      this.onLocated,
      this.locate,
      this.autoLocate = true,
      this.tileProvider});
  @override
  State<OsmMap> createState() => _OsmMapState();
}

class _OsmMapState extends State<OsmMap> {
  final controller = MapController();
  LatLng? user;
  bool locating = false, ready = false, userMoved = false;
  String? status, tileError;
  bool tileFailureScheduled = false;
  @override
  void initState() {
    super.initState();
    if (widget.autoLocate)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) locate();
      });
  }

  @override
  void didUpdateWidget(OsmMap old) {
    super.didUpdateWidget(old);
    if (ready &&
        user == null &&
        !userMoved &&
        widget.initialCenter != null &&
        widget.initialCenter != old.initialCenter)
      controller.move(widget.initialCenter!, 12);
    if (ready && widget.selected != null && widget.selected != old.selected) {
      userMoved = true;
      controller.move(widget.selected!, 15);
    }
  }

  Future<void> locate() async {
    if (locating) return;
    setState(() {
      locating = true;
      status = null;
    });
    try {
      final value = await (widget.locate?.call() ?? currentDeviceLocation());
      if (!mounted) return;
      final point = mapPoint(value);
      if (point == null)
        throw ApiException('GPS_DENIED',
            'Не удалось определить местоположение. Выберите точку вручную.');
      setState(() => user = point);
      if (ready && !userMoved) controller.move(point, 14);
      if (!userMoved) widget.onLocated?.call(point);
    } catch (error) {
      if (mounted)
        setState(() => status = error is ApiException
            ? error.message
            : 'Местоположение недоступно. Выберите точку вручную.');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  void failedTile() {
    if (tileError != null || tileFailureScheduled) return;
    tileFailureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tileFailureScheduled = false;
      if (mounted)
        setState(() => tileError =
            'Не удалось загрузить карту. Проверьте подключение и повторите.');
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        FlutterMap(
            mapController: controller,
            options: MapOptions(
                initialCenter: widget.initialCenter ??
                    widget.selected ??
                    const LatLng(0, 0),
                initialZoom:
                    widget.initialCenter != null || widget.selected != null
                        ? 12
                        : 2,
                minZoom: 2,
                maxZoom: 19,
                onMapReady: () {
                  ready = true;
                  if (user != null && !userMoved) controller.move(user!, 14);
                },
                onPositionChanged: (_, gesture) {
                  if (gesture) userMoved = true;
                },
                onTap: widget.onSelected == null
                    ? null
                    : (_, point) {
                        userMoved = true;
                        widget.onSelected!(point);
                      }),
            children: [
              TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'kz.joba.services_marketplace',
                  tileProvider: widget.tileProvider,
                  maxNativeZoom: 19,
                  errorTileCallback: (_, __, ___) => failedTile()),
              MarkerLayer(markers: [
                ...widget.markers,
                if (user != null)
                  Marker(
                      point: user!,
                      width: 22,
                      height: 22,
                      child: Semantics(
                          label: localize(context, 'Моё местоположение'),
                          child: Container(
                              decoration: BoxDecoration(
                                  color: const Color(0xFF245BDB),
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 3),
                                  boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 5)
                              ])))),
                if (widget.selected != null)
                  Marker(
                      point: widget.selected!,
                      width: 42,
                      height: 48,
                      child: const Icon(Icons.location_pin,
                          size: 42, color: Color(0xFFD63D39)))
              ]),
            ]),
        Positioned(
            right: 12,
            bottom: 45,
            child: FloatingActionButton.small(
                heroTag: null,
                tooltip: localize(context, 'Моё местоположение'),
                onPressed: locating
                    ? null
                    : () {
                        userMoved = false;
                        locate();
                      },
                child: locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location))),
        Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ColoredBox(
                color: Colors.white,
                child: TextButton(
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        minimumSize: const Size(0, 28)),
                    onPressed: () => launchUrl(
                        Uri.parse('https://www.openstreetmap.org/copyright'),
                        mode: LaunchMode.externalApplication),
                    child: const Text('© OpenStreetMap contributors',
                        style: TextStyle(fontSize: 11))))),
        if (status != null || tileError != null)
          Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: Material(
                  color: Colors.white,
                  elevation: 2,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(children: [
                        Expanded(
                            child: UiText(status ?? tileError!,
                                style: const TextStyle(fontSize: 12))),
                        IconButton(
                            tooltip: localize(context, 'Закрыть'),
                            onPressed: () => setState(() {
                                  status = null;
                                  tileError = null;
                                }),
                            icon: const Icon(Icons.close, size: 18))
                      ])))),
      ]);
}
