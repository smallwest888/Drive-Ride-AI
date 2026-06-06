"use client";

import { useEffect, useRef, useState } from "react";
import type { Language, LocationPoint, Plan } from "@drive-ride/shared";

declare global {
  interface Window {
    CESIUM_BASE_URL?: string;
    Cesium?: any;
  }
}

type Props = {
  plan: Plan | null;
  currentLocation: LocationPoint | null;
  language: Language;
};

const CESIUM_SCRIPT_ID = "drive-ride-cesium-script";
const CESIUM_STYLE_ID = "drive-ride-cesium-style";
const CESIUM_BASE_URL = "https://cdn.jsdelivr.net/npm/cesium@1.136.0/Build/Cesium/";

const DEFAULT_CENTER = {
  longitude: 9.9937,
  latitude: 53.5511
};

const CAMERA_LIMITS = {
  minHeight: 240000,
  maxHeight: 1650000,
  defaultHeight: 620000,
  defaultPitch: -1.54,
  minPitch: -1.56,
  maxPitch: -1.36
};

export function PlanetMap({ plan, currentLocation, language }: Props) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const viewerRef = useRef<any>(null);
  const [ready, setReady] = useState(false);
  const [loadError, setLoadError] = useState("");

  useEffect(() => {
    let cancelled = false;

    async function boot() {
      try {
        const Cesium = await ensureCesiumLoaded();
        if (cancelled || !containerRef.current || viewerRef.current) return;

        viewerRef.current = createViewer(Cesium, containerRef.current);
        setReady(true);
      } catch {
        if (!cancelled) {
          setLoadError(getMapText(language, "loadFailed"));
        }
      }
    }

    boot().catch(() => undefined);

    return () => {
      cancelled = true;
      if (viewerRef.current) {
        viewerRef.current.destroy();
        viewerRef.current = null;
      }
    };
  }, []);

  useEffect(() => {
    if (!ready || !viewerRef.current || !window.Cesium) return;
    renderScene(window.Cesium, viewerRef.current, plan, currentLocation, language);
  }, [ready, plan, currentLocation, language]);

  return (
    <div className="planet-frame">
      <div ref={containerRef} className="planet-canvas" />
      {!ready && !loadError ? <div className="planet-overlay">{getMapText(language, "loading")}</div> : null}
      {loadError ? <div className="planet-overlay">{loadError}</div> : null}
    </div>
  );
}

async function ensureCesiumLoaded() {
  if (window.Cesium) {
    return window.Cesium;
  }

  window.CESIUM_BASE_URL = CESIUM_BASE_URL;

  if (!document.getElementById(CESIUM_STYLE_ID)) {
    const link = document.createElement("link");
    link.id = CESIUM_STYLE_ID;
    link.rel = "stylesheet";
    link.href = `${CESIUM_BASE_URL}Widgets/widgets.css`;
    document.head.appendChild(link);
  }

  await new Promise<void>((resolve, reject) => {
    const existing = document.getElementById(CESIUM_SCRIPT_ID) as HTMLScriptElement | null;
    if (existing?.dataset.ready === "true") {
      resolve();
      return;
    }

    const script = existing ?? document.createElement("script");
    if (!existing) {
      script.id = CESIUM_SCRIPT_ID;
      script.src = `${CESIUM_BASE_URL}Cesium.js`;
      script.async = true;
      document.body.appendChild(script);
    }

    script.onload = () => {
      script.dataset.ready = "true";
      resolve();
    };
    script.onerror = () => reject(new Error("Cesium CDN failed to load."));
  });

  if (!window.Cesium) {
    throw new Error("Cesium did not initialize.");
  }

  return window.Cesium;
}

function createViewer(Cesium: any, container: HTMLDivElement) {
  Cesium.Ion.defaultAccessToken = undefined;
  const viewer = new Cesium.Viewer(container, {
    animation: false,
    baseLayer: false,
    baseLayerPicker: false,
    fullscreenButton: false,
    geocoder: false,
    homeButton: false,
    infoBox: false,
    navigationHelpButton: false,
    sceneModePicker: false,
    selectionIndicator: false,
    timeline: false,
    terrainProvider: new Cesium.EllipsoidTerrainProvider(),
    shouldAnimate: true
  });

  viewer.imageryLayers.removeAll();
  viewer.imageryLayers.addImageryProvider(
    new Cesium.OpenStreetMapImageryProvider({
      url: "https://tile.openstreetmap.org/"
    })
  );

  viewer.scene.globe.enableLighting = true;
  viewer.scene.globe.baseColor = Cesium.Color.fromCssColorString("#081121");
  viewer.scene.skyAtmosphere.hueShift = -0.08;
  viewer.scene.skyAtmosphere.saturationShift = 0.15;
  viewer.scene.skyAtmosphere.brightnessShift = 0.04;
  viewer.scene.backgroundColor = Cesium.Color.fromCssColorString("#040916");
  viewer.scene.fog.enabled = true;
  viewer.scene.fog.density = 0.00015;
  viewer.cesiumWidget.creditContainer.style.display = "none";
  viewer.scene.screenSpaceCameraController.enableCollisionDetection = true;
  viewer.scene.screenSpaceCameraController.minimumZoomDistance = CAMERA_LIMITS.minHeight;
  viewer.scene.screenSpaceCameraController.maximumZoomDistance = CAMERA_LIMITS.maxHeight;

  setCameraView(Cesium, viewer, DEFAULT_CENTER.longitude, DEFAULT_CENTER.latitude, CAMERA_LIMITS.defaultHeight, 0, CAMERA_LIMITS.defaultPitch);
  attachCameraGuards(Cesium, viewer);

  return viewer;
}

function renderScene(Cesium: any, viewer: any, plan: Plan | null, currentLocation: LocationPoint | null, language: Language) {
  viewer.entities.removeAll();

  if (!plan) {
    if (currentLocation) {
      addPoint(Cesium, viewer, currentLocation, "#145dff", 20, getMapText(language, "currentLocation"));
      flyToPoint(Cesium, viewer, currentLocation.longitude, currentLocation.latitude, 560000);
    } else {
      setCameraView(Cesium, viewer, DEFAULT_CENTER.longitude, DEFAULT_CENTER.latitude, CAMERA_LIMITS.defaultHeight, 0, CAMERA_LIMITS.defaultPitch);
    }
    return;
  }

  for (const [index, segment] of plan.routeSegments.entries()) {
    if (segment.path.length < 2) continue;

    const positions = Cesium.Cartesian3.fromDegreesArray(segment.path.flatMap((point) => [point.longitude, point.latitude]));

    viewer.entities.add({
      name: segment.title,
      polyline: {
        positions,
        width: segment.kind === "walk" ? 6 : segment.kind === "transit" ? 9 : 10,
        clampToGround: false,
        material: buildSegmentMaterial(Cesium, segment.kind),
        arcType: Cesium.ArcType.GEODESIC
      }
    });

    if (index === 0) {
      addPoint(Cesium, viewer, segment.path[0], "#145dff", 22, segment.path[0].label || getMapText(language, "origin"));
    }
  }

  if (plan.parking) {
    addPoint(
      Cesium,
      viewer,
      {
        label: plan.parking.name,
        latitude: plan.parking.latitude,
        longitude: plan.parking.longitude
      },
      "#00b894",
      18,
      plan.parking.name
    );
  }

  const destination = plan.routePoints.at(-1);
  if (destination) {
    addPoint(Cesium, viewer, destination, "#ff7a1a", 22, destination.label || getMapText(language, "destination"));
  }

  focusRoute(Cesium, viewer, plan);
}

function buildSegmentMaterial(Cesium: any, kind: string) {
  if (kind === "walk") {
    return new Cesium.PolylineOutlineMaterialProperty({
      color: Cesium.Color.fromCssColorString("#ff8a1f"),
      outlineColor: Cesium.Color.fromCssColorString("rgba(255,255,255,0.92)"),
      outlineWidth: 2
    });
  }

  if (kind === "transit") {
    return new Cesium.PolylineOutlineMaterialProperty({
      color: Cesium.Color.fromCssColorString("#b100ff"),
      outlineColor: Cesium.Color.fromCssColorString("rgba(255,255,255,0.96)"),
      outlineWidth: 2.4
    });
  }

  return new Cesium.PolylineOutlineMaterialProperty({
    color: Cesium.Color.fromCssColorString("#145dff"),
    outlineColor: Cesium.Color.fromCssColorString("rgba(255,255,255,0.98)"),
    outlineWidth: 2.8
  });
}

function addPoint(Cesium: any, viewer: any, point: LocationPoint | undefined | null, color: string, pixelSize: number, label: string) {
  if (!point) return;

  viewer.entities.add({
    position: Cesium.Cartesian3.fromDegrees(point.longitude, point.latitude),
    point: {
      pixelSize,
      color: Cesium.Color.fromCssColorString(color),
      outlineColor: Cesium.Color.fromCssColorString("#ffffff"),
      outlineWidth: 3
    },
    label: {
      text: label,
      font: "600 14px sans-serif",
      fillColor: Cesium.Color.fromCssColorString("#16243d"),
      showBackground: true,
      backgroundColor: Cesium.Color.fromCssColorString("rgba(255, 255, 255, 0.92)"),
      pixelOffset: new Cesium.Cartesian2(0, -28)
    }
  });
}

function attachCameraGuards(Cesium: any, viewer: any) {
  let applying = false;

  viewer.camera.changed.addEventListener(() => {
    if (applying) return;
    applying = true;

    try {
      const camera = viewer.camera;
      const center = getViewCenter(Cesium, viewer) ?? DEFAULT_CENTER;
      const rawHeight = camera.positionCartographic?.height ?? CAMERA_LIMITS.defaultHeight;
      const height = clamp(rawHeight, CAMERA_LIMITS.minHeight, CAMERA_LIMITS.maxHeight);
      const pitch = clamp(camera.pitch ?? CAMERA_LIMITS.defaultPitch, CAMERA_LIMITS.minPitch, CAMERA_LIMITS.maxPitch);

      const invalidHeight = !Number.isFinite(rawHeight) || rawHeight > CAMERA_LIMITS.maxHeight * 1.2 || rawHeight < CAMERA_LIMITS.minHeight * 0.8;
      const invalidPitch = (camera.pitch ?? CAMERA_LIMITS.defaultPitch) > CAMERA_LIMITS.maxPitch || (camera.pitch ?? CAMERA_LIMITS.defaultPitch) < CAMERA_LIMITS.minPitch;

      if (invalidHeight || invalidPitch) {
        setCameraView(Cesium, viewer, center.longitude, center.latitude, invalidHeight ? CAMERA_LIMITS.defaultHeight : height, camera.heading ?? 0, pitch);
      }
    } finally {
      applying = false;
    }
  });
}

function flyToPoint(Cesium: any, viewer: any, longitude: number, latitude: number, height: number) {
  viewer.camera.flyTo({
    destination: Cesium.Cartesian3.fromDegrees(longitude, latitude, clamp(height, CAMERA_LIMITS.minHeight, CAMERA_LIMITS.maxHeight)),
    orientation: {
      heading: viewer.camera.heading ?? 0,
      pitch: CAMERA_LIMITS.defaultPitch,
      roll: 0
    },
    duration: 1.2
  });
}

function focusRoute(Cesium: any, viewer: any, plan: Plan) {
  const allPoints = [...plan.routePoints, ...plan.routePath, ...plan.routeSegments.flatMap((segment) => segment.path)];

  if (allPoints.length === 0) {
    setCameraView(Cesium, viewer, DEFAULT_CENTER.longitude, DEFAULT_CENTER.latitude, CAMERA_LIMITS.defaultHeight, 0, CAMERA_LIMITS.defaultPitch);
    return;
  }

  let minLongitude = allPoints[0].longitude;
  let maxLongitude = allPoints[0].longitude;
  let minLatitude = allPoints[0].latitude;
  let maxLatitude = allPoints[0].latitude;

  for (const point of allPoints) {
    minLongitude = Math.min(minLongitude, point.longitude);
    maxLongitude = Math.max(maxLongitude, point.longitude);
    minLatitude = Math.min(minLatitude, point.latitude);
    maxLatitude = Math.max(maxLatitude, point.latitude);
  }

  const centerLongitude = (minLongitude + maxLongitude) / 2;
  const centerLatitude = (minLatitude + maxLatitude) / 2;
  const span = Math.max(maxLongitude - minLongitude, maxLatitude - minLatitude);
  const height = clamp(220000 + span * 850000, CAMERA_LIMITS.minHeight, 720000);

  viewer.camera.flyTo({
    destination: Cesium.Cartesian3.fromDegrees(centerLongitude, centerLatitude, height),
    orientation: {
      heading: viewer.camera.heading ?? 0,
      pitch: CAMERA_LIMITS.defaultPitch,
      roll: 0
    },
    duration: 1.4
  });
}

function setCameraView(Cesium: any, viewer: any, longitude: number, latitude: number, height: number, heading: number, pitch: number) {
  viewer.camera.setView({
    destination: Cesium.Cartesian3.fromDegrees(longitude, latitude, clamp(height, CAMERA_LIMITS.minHeight, CAMERA_LIMITS.maxHeight)),
    orientation: {
      heading,
      pitch: clamp(pitch, CAMERA_LIMITS.minPitch, CAMERA_LIMITS.maxPitch),
      roll: 0
    }
  });
}

function getViewCenter(Cesium: any, viewer: any) {
  const rectangle = viewer.camera.computeViewRectangle(viewer.scene.globe.ellipsoid);
  if (!rectangle) return null;

  return {
    longitude: Cesium.Math.toDegrees((rectangle.west + rectangle.east) / 2),
    latitude: Cesium.Math.toDegrees((rectangle.south + rectangle.north) / 2)
  };
}

function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max);
}

function getMapText(language: Language, key: "loading" | "loadFailed" | "currentLocation" | "origin" | "destination") {
  const zh = {
    loading: "正在加载 3D 地球仪...",
    loadFailed: "3D 地球仪暂时无法显示。",
    currentLocation: "当前位置",
    origin: "出发点",
    destination: "目的地"
  };

  const en = {
    loading: "Loading 3D globe...",
    loadFailed: "The 3D globe is temporarily unavailable.",
    currentLocation: "Current location",
    origin: "Origin",
    destination: "Destination"
  };

  return (language === "zh" ? zh : en)[key];
}
