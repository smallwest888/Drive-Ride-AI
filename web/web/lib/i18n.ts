import type { Language, Plan, PlanningResponse, RouteSegment } from "@drive-ride/shared";

type Dictionary = {
  brand: string;
  tag: string;
  menu: {
    title: string;
    tripRequest: string;
    origin: string;
    destination: string;
    requirements: string;
    settings: string;
    language: string;
    routeOptions: string;
  };
  fields: {
    tripRequestLabel: string;
    tripRequestPlaceholder: string;
    tripRequestSubmit: string;
    originLabel: string;
    originPlaceholder: string;
    destinationLabel: string;
    destinationPlaceholder: string;
    requirementsLabel: string;
    requirementsPlaceholder: string;
    priorityLabel: string;
    budgetLabel: string;
    departureLabel: string;
    parkingLabel: string;
    useDeviceLocation: string;
    refreshLocation: string;
    languageLabel: string;
    settingsHint: string;
    generate: string;
  };
  voice: {
    idle: string;
    listening: string;
    stop: string;
    processing: string;
    retry: string;
    process: string;
    replay: string;
    subtitle: string;
    transcriptTitle: string;
    transcriptHint: string;
    speechFailed: string;
    listeningHint: string;
    waitingSubtitle: string;
  };
  route: {
    recommended: string;
    alternatives: string;
    summary: string;
    steps: string;
    openDrawer: string;
    closeDrawer: string;
    openDriving: string;
    openTransit: string;
    openSegment: string;
    liveTraffic: string;
    liveFare: string;
    noResult: string;
    candidateCount: (count: number) => string;
  };
  status: {
    locating: string;
    locationReady: string;
    locationUnavailable: string;
    transcriptionUnavailable: string;
    planningFailed: string;
    noDestination: string;
    emptyTripRequest: string;
  };
  priorities: Record<"balanced" | "cheapest" | "fastest" | "comfortable" | "lowCarbon", string>;
  packages: Record<string, string>;
  metrics: {
    totalCost: string;
    duration: string;
    comfort: string;
    carbon: string;
    transfers: string;
    walking: string;
    parking: string;
  };
};

export const dictionaries: Record<Language, Dictionary> = {
  zh: {
    brand: "Drive&Ride",
    tag: "3D 地球仪 AI 出行规划",
    menu: {
      title: "出行控制台",
      tripRequest: "输入行程要求",
      origin: "输入出发地",
      destination: "输入目的地",
      requirements: "其他要求",
      settings: "设置",
      language: "更改语言",
      routeOptions: "可选路径"
    },
    fields: {
      tripRequestLabel: "输入行程要求",
      tripRequestPlaceholder: "例如：我要从当前所在位置去汉堡机场，预算 20 欧元以内，尽量少换乘，最好在 18:30 前到达。",
      tripRequestSubmit: "开始处理行程要求",
      originLabel: "出发地",
      originPlaceholder: "默认使用当前设备位置，也可以手动输入地址、商圈或地标。",
      destinationLabel: "目的地",
      destinationPlaceholder: "输入车站、机场、商圈、场馆或完整地址。",
      requirementsLabel: "其他要求",
      requirementsPlaceholder: "例如：预算 15 欧元以内、尽量少换乘、步行不超过 8 分钟、适合带行李、避免晚高峰。",
      priorityLabel: "优先策略",
      budgetLabel: "预算上限（欧元）",
      departureLabel: "出发时间",
      parkingLabel: "预计停车时长（小时）",
      useDeviceLocation: "默认使用当前设备位置",
      refreshLocation: "重新获取设备位置",
      languageLabel: "界面语言",
      settingsHint: "这些设置会影响路径排序、停车场推荐以及最终建议。",
      generate: "生成路径方案"
    },
    voice: {
      idle: "你想去哪里",
      listening: "正在聆听，请说出目的地和要求",
      stop: "停止识别",
      processing: "AI 正在分析路线",
      retry: "重新说一遍",
      process: "开始处理",
      replay: "重新播放",
      subtitle: "AI 语音回复字幕",
      transcriptTitle: "识别结果",
      transcriptHint: "确认文字无误后，再点击一次开始处理。",
      speechFailed: "语音输入没有成功，请改用左侧文字输入。",
      listeningHint: "点击开始录音，再点击一次结束识别。",
      waitingSubtitle: "AI 处理完成后，这里会显示语音回复字幕。"
    },
    route: {
      recommended: "推荐路径",
      alternatives: "其他备选",
      summary: "方案摘要",
      steps: "分段路线",
      openDrawer: "查看路径",
      closeDrawer: "收起路径",
      openDriving: "在谷歌地图查看驾车段",
      openTransit: "在谷歌地图查看公共交通段",
      openSegment: "在谷歌地图中查看",
      liveTraffic: "实时路况",
      liveFare: "实时票价",
      noResult: "先发起一次规划，这里会显示可选路径和地图跳转入口。",
      candidateCount: (count: number) => `${count} 条候选路径`
    },
    status: {
      locating: "正在获取当前位置...",
      locationReady: "当前位置已更新",
      locationUnavailable: "暂时无法获取设备位置。",
      transcriptionUnavailable: "这段语音没有识别成功，请再试一次。",
      planningFailed: "这次路线规划没有成功，请稍后再试。",
      noDestination: "请先输入目的地，或者直接使用底部语音入口。",
      emptyTripRequest: "请先输入完整的行程要求。"
    },
    priorities: {
      balanced: "综合平衡",
      cheapest: "最便宜",
      fastest: "最快",
      comfortable: "最舒适",
      lowCarbon: "最低碳排"
    },
    packages: {
      recommended: "推荐",
      cheapest: "最便宜",
      fastest: "最快",
      comfortable: "最舒适",
      lowCarbon: "最低碳排",
      balanced: "平衡方案"
    },
    metrics: {
      totalCost: "总费用",
      duration: "总时长",
      comfort: "舒适度",
      carbon: "碳排放",
      transfers: "换乘",
      walking: "步行",
      parking: "停车"
    }
  },
  en: {
    brand: "Drive&Ride",
    tag: "3D globe AI trip planning",
    menu: {
      title: "Trip console",
      tripRequest: "Trip request",
      origin: "Origin",
      destination: "Destination",
      requirements: "Requirements",
      settings: "Settings",
      language: "Language",
      routeOptions: "Route options"
    },
    fields: {
      tripRequestLabel: "Type your trip request",
      tripRequestPlaceholder: "Example: I want to go to Hamburg Airport from my current location, stay under EUR 20, keep transfers low, and arrive before 6:30 pm.",
      tripRequestSubmit: "Process typed request",
      originLabel: "Origin",
      originPlaceholder: "Use your current device location by default, or type an address, district, or landmark.",
      destinationLabel: "Destination",
      destinationPlaceholder: "Enter a station, airport, venue, district, or full address.",
      requirementsLabel: "Other requirements",
      requirementsPlaceholder: "Example: under EUR 15, fewer transfers, no more than 8 minutes of walking, luggage-friendly, avoid rush hour.",
      priorityLabel: "Priority",
      budgetLabel: "Budget limit (EUR)",
      departureLabel: "Departure time",
      parkingLabel: "Parking duration (hours)",
      useDeviceLocation: "Use current device location by default",
      refreshLocation: "Refresh device location",
      languageLabel: "Interface language",
      settingsHint: "These settings influence route ranking, parking recommendations, and the final suggestion.",
      generate: "Generate route options"
    },
    voice: {
      idle: "Where do you want to go",
      listening: "Listening. Say your destination and what matters to you.",
      stop: "Stop listening",
      processing: "AI is analyzing the routes",
      retry: "Try again",
      process: "Process request",
      replay: "Replay",
      subtitle: "AI voice subtitle",
      transcriptTitle: "Transcript",
      transcriptHint: "Check the text, then tap again to process it.",
      speechFailed: "Voice input did not come through. Please use the left panel instead.",
      listeningHint: "Tap once to start recording, then tap again to stop.",
      waitingSubtitle: "The AI voice subtitle will appear here after the route is generated."
    },
    route: {
      recommended: "Recommended route",
      alternatives: "Alternatives",
      summary: "Summary",
      steps: "Route segments",
      openDrawer: "Open routes",
      closeDrawer: "Close routes",
      openDriving: "Open driving leg in Google Maps",
      openTransit: "Open transit leg in Google Maps",
      openSegment: "Open in Google Maps",
      liveTraffic: "Live traffic",
      liveFare: "Live fare",
      noResult: "Run a trip first. This panel will show route choices and Google Maps links.",
      candidateCount: (count: number) => `${count} candidate routes`
    },
    status: {
      locating: "Detecting current location...",
      locationReady: "Current location updated",
      locationUnavailable: "We could not get your device location just now.",
      transcriptionUnavailable: "We could not catch that voice request. Please try again.",
      planningFailed: "This route request did not go through. Please try again.",
      noDestination: "Enter a destination first or use the voice control at the bottom.",
      emptyTripRequest: "Please enter your trip request first."
    },
    priorities: {
      balanced: "Balanced",
      cheapest: "Cheapest",
      fastest: "Fastest",
      comfortable: "Most comfortable",
      lowCarbon: "Lowest carbon"
    },
    packages: {
      recommended: "Recommended",
      cheapest: "Cheapest",
      fastest: "Fastest",
      comfortable: "Most comfortable",
      lowCarbon: "Lowest carbon",
      balanced: "Balanced"
    },
    metrics: {
      totalCost: "Total cost",
      duration: "Total time",
      comfort: "Comfort",
      carbon: "Carbon",
      transfers: "Transfers",
      walking: "Walking",
      parking: "Parking"
    }
  }
};

export function packageLabel(language: Language, tag: Plan["strategyTag"]) {
  return dictionaries[language].packages[tag];
}

export function summarizePlans(response: PlanningResponse) {
  const recommendation = response.plans.find((plan) => plan.planId === response.recommendedPlanId) ?? response.plans[0] ?? null;
  return {
    recommendation,
    packageCards: response.plans
  };
}

export function cleanPlanTitle(language: Language, plan: Plan) {
  if (plan.parking) {
    return language === "zh" ? `停在 ${plan.parking.name}` : `Park at ${plan.parking.name}`;
  }

  if (plan.transitDuration === 0) {
    return language === "zh" ? "直接开车进入城区" : "Drive directly into the city";
  }

  if (plan.drivingDuration === 0) {
    return language === "zh" ? "全程公共交通" : "Public transit only";
  }

  return language === "zh" ? "换乘停车方案" : "Park-and-ride option";
}

export function cleanPlanSummary(language: Language, plan: Plan) {
  if (plan.parking) {
    return language === "zh"
      ? `先开车到 ${plan.parking.name}，再换乘公共交通进城，兼顾停车成本和进城效率。`
      : `Drive to ${plan.parking.name} first, then continue into the city by transit.`;
  }

  if (plan.transitDuration === 0) {
    return language === "zh"
      ? "适合短时办事或不想换乘的情况，但要留意市区停车成本。"
      : "Best for short errands or when you prefer to avoid transfers, though city-center parking may cost more.";
  }

  return language === "zh"
    ? "全程公共交通，通常更省心，也更环保。"
    : "Transit all the way, often the easiest and most sustainable option.";
}

export function cleanSegmentTitle(language: Language, segment: RouteSegment, index: number) {
  switch (segment.kind) {
    case "drive":
      return language === "zh" ? `驾车路线 ${index + 1}` : `Driving leg ${index + 1}`;
    case "transit":
      return language === "zh" ? `公共交通 ${index + 1}` : `Transit leg ${index + 1}`;
    case "walk":
      return language === "zh" ? `步行路线 ${index + 1}` : `Walking leg ${index + 1}`;
    case "park":
      return language === "zh" ? "停车" : "Parking";
    default:
      return segment.title;
  }
}

export function cleanSegmentDescription(language: Language, segment: RouteSegment) {
  if (segment.description && !containsMojibake(segment.description)) {
    return segment.description;
  }

  if (segment.kind === "park") {
    const fare = Number(segment.metadata.fare ?? 0);
    return language === "zh"
      ? fare > 0
        ? `预计停车费用约 EUR ${fare.toFixed(2)}。`
        : "这一段停车不需要额外费用。"
      : fare > 0
        ? `Estimated parking cost: EUR ${fare.toFixed(2)}.`
        : "No additional parking fee on this parking segment.";
  }

  if (segment.kind === "drive") {
    return language === "zh" ? "这段驾车路线会直接显示在地图上。" : "This driving leg is drawn directly on the map.";
  }

  if (segment.kind === "transit") {
    const stopCount = Number(segment.metadata.stopCount ?? 0);
    return language === "zh"
      ? stopCount > 0
        ? `公共交通路线，预计经过 ${stopCount} 站。`
        : "公共交通路线。"
      : stopCount > 0
        ? `Transit leg with about ${stopCount} stops.`
        : "Transit leg.";
  }

  if (segment.kind === "walk") {
    return language === "zh" ? "步行连接路段。" : "Walking connector segment.";
  }

  return segment.description;
}

export function cleanRouteWarning(_language: Language, _plan: Plan) {
  return null;
}

function containsMojibake(value: string) {
  return /[�茂锟]/.test(value);
}
