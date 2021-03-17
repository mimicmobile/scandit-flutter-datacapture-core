/*
 * This file is part of the Scandit Data Capture SDK
 *
 * Copyright (C) 2020- Scandit AG. All rights reserved.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'common.dart' as common;
import 'data_capture_context.dart';
import 'defaults.dart';
import 'focus_gesture.dart';
import 'function_names.dart';
import 'zoom_gesture.dart';

abstract class DataCaptureOverlay extends common.Serializable {
  final String _type;

  DataCaptureView get view;

  set view(DataCaptureView newValue);

  DataCaptureOverlay(this._type);

  @override
  Map<String, dynamic> toMap() {
    return {'type': _type};
  }
}

abstract class DataCaptureViewListener {
  void didChangeSize(DataCaptureView view, common.Size size, common.Orientation orientation);
}

// ignore: must_be_immutable
class DataCaptureView extends StatefulWidget implements common.Serializable {
  PrivateDataCaptureContext _dataCaptureContext;
  common.MarginsWithUnit _scanAreaMargins;
  common.PointWithUnit _pointOfInterest;
  common.Anchor _logoAnchor;
  common.PointWithUnit _logoOffset;
  final List<DataCaptureOverlay> _overlays = [];
  final List<DataCaptureViewListener> _listeners = [];
  FocusGesture _focusGesture;
  ZoomGesture _zoomGesture;

  final EventChannel _viewDidChangeSizeEventChannel =
      const EventChannel('com.scandit.datacapture.core.event/datacapture_view#didChangeSize');
  final _DataCaptureViewController _controller = _DataCaptureViewController();
  StreamSubscription _streamSubscription;

  DataCaptureView._(this._dataCaptureContext) : super() {
    if (_dataCaptureContext != null) {
      _dataCaptureContext.view = this;
      _dataCaptureContext.initialize();
    }
  }

  factory DataCaptureView.forContext(DataCaptureContext dataCaptureContext) {
    return DataCaptureView._(dataCaptureContext);
  }

  @override
  State<StatefulWidget> createState() => _DataCaptureViewState(dataCaptureContext);

  DataCaptureContext get dataCaptureContext {
    return _dataCaptureContext;
  }

  set dataCaptureContext(DataCaptureContext newValue) {
    _dataCaptureContext = newValue;
    if (_dataCaptureContext != null) {
      _dataCaptureContext.view = this;
      _dataCaptureContext.initialize();
    }
  }

  common.MarginsWithUnit get scanAreaMargins {
    return _scanAreaMargins;
  }

  set scanAreaMargins(common.MarginsWithUnit newValue) {
    _scanAreaMargins = newValue;
    _updateContext();
  }

  common.PointWithUnit get pointOfInterest {
    return _pointOfInterest;
  }

  set pointOfInterest(common.PointWithUnit newValue) {
    _pointOfInterest = newValue;
    _updateContext();
  }

  common.Anchor get logoAnchor {
    return _logoAnchor;
  }

  set logoAnchor(common.Anchor newValue) {
    _logoAnchor = newValue;
    _updateContext();
  }

  common.PointWithUnit get logoOffset {
    return _logoOffset;
  }

  set logoOffset(common.PointWithUnit newValue) {
    _logoOffset = newValue;
    _updateContext();
  }

  FocusGesture get focusGesture {
    return _focusGesture;
  }

  set focusGesture(FocusGesture newValue) {
    _focusGesture = newValue;
    _updateContext();
  }

  ZoomGesture get zoomGesture {
    return _zoomGesture;
  }

  set zoomGesture(ZoomGesture newValue) {
    _zoomGesture = newValue;
    _updateContext();
  }

  @override
  Map<String, dynamic> toMap() {
    var json = <String, dynamic>{};
    if (_scanAreaMargins != null) {
      json['scanAreaMargins'] = _scanAreaMargins.toMap();
    }
    if (_pointOfInterest != null) {
      json['pointOfInterest'] = _pointOfInterest.toMap();
    }
    if (_logoAnchor != null) {
      json['logoAnchor'] = _logoAnchor.jsonValue;
    }
    if (_logoOffset != null) {
      json['logoOffset'] = _logoOffset.toMap();
    }
    json['overlays'] = _overlays.map((overlay) => overlay.toMap()).toList();
    json['focusGesture'] = _focusGesture != null ? _focusGesture.toMap() : null;
    json['zoomGesture'] = _zoomGesture != null ? _zoomGesture.toMap() : null;
    return json;
  }

  void addOverlay(DataCaptureOverlay overlay) {
    if (_overlays.contains(overlay)) {
      return;
    }
    _overlays.add(overlay);
    _updateContext();
  }

  void removeOverlay(DataCaptureOverlay overlay) {
    if (!_overlays.contains(overlay)) {
      return;
    }
    _overlays.remove(overlay);
    _updateContext();
  }

  void addListener(DataCaptureViewListener listener) {
    if (_listeners.isEmpty) {
      _registerListener();
    }

    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(DataCaptureViewListener listener) {
    _listeners.remove(listener);

    if (_listeners.isEmpty) {
      _unregisterListener();
    }
  }

  Future<common.Point> viewPointForFramePoint(common.Point point) {
    return _controller._viewPointForFramePoint(point);
  }

  Future<common.Quadrilateral> viewQuadrilateralForFrameQuadrilateral(common.Quadrilateral quadrilateral) {
    return _controller._viewQuadrilateralForFrameQuadrilateral(quadrilateral);
  }

  void _registerListener() {
    _unregisterListener();
    _streamSubscription = _viewDidChangeSizeEventChannel.receiveBroadcastStream().listen((event) {
      var json = jsonDecode(event as String);
      var size = common.Size.fromJSON(json['size']);
      var orientation = common.OrientationDeserializer.fromJSON(json['orientation']);
      _notifyListenersOfViewDidChangeSize(size, orientation);
    });
  }

  void _unregisterListener() {
    if (_streamSubscription != null) {
      _streamSubscription.cancel();
    }
    _streamSubscription = null;
  }

  void _notifyListenersOfViewDidChangeSize(common.Size size, common.Orientation orientation) {
    for (var listener in _listeners) {
      listener.didChangeSize(this, size, orientation);
    }
  }

  void _updateContext() {
    if (_dataCaptureContext != null) _dataCaptureContext.update();
  }
}

class _DataCaptureViewController {
  final MethodChannel _methodChannel = Defaults.channel;

  Future<common.Point> _viewPointForFramePoint(common.Point point) {
    var args = jsonEncode(point.toMap());
    return _methodChannel
        .invokeMethod(FunctionNames.viewPointForFramePoint, args)
        .then((value) => common.Point.fromJSON(jsonDecode(value)));
  }

  Future<common.Quadrilateral> _viewQuadrilateralForFrameQuadrilateral(common.Quadrilateral quadrilateral) {
    var args = jsonEncode(quadrilateral.toMap());
    return _methodChannel
        .invokeMethod(FunctionNames.viewQuadrilateralForFrameQuadrilateral, args)
        .then((value) => common.Quadrilateral.fromJSON(jsonDecode(value)));
  }
}

class _DataCaptureViewState extends State<DataCaptureView> {
  DataCaptureContext _dataCaptureContext;

  DataCaptureContext get dataCaptureContext => _dataCaptureContext;

  set dataCaptureContext(DataCaptureContext newValue) {
    _dataCaptureContext = newValue;
    if (_dataCaptureContext != null) {
      _dataCaptureContext.view = widget;
      _dataCaptureContext.initialize();
    }
  }

  _DataCaptureViewState(this._dataCaptureContext);

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return AndroidView(
        viewType: 'com.scandit.DataCaptureView',
      );
    } else {
      return UiKitView(
        viewType: 'com.scandit.DataCaptureView',
      );
    }
  }
}
