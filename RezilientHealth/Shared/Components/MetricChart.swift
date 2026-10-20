import Charts
import SwiftUI

/// Bars for totals (steps, sleep), a smoothed line with a soft area for
/// resting heart rate. The full style supports scrubbing: drag or tap to see
/// a day's value, with a haptic tick per day. Gaps stay visible as gray
/// columns and are never bridged by the line.
struct MetricChart: View {
    enum Style { case sparkline, full }

    let card: MetricCardState
    let style: Style

    @State private var rawSelection: Date?
    @State private var hasAppeared = false

    private var isFull: Bool { style == .full }
    private var isDense: Bool { card.chart.count > 31 }

    private var selected: MetricCardState.ChartPoint? {
        guard let rawSelection else { return nil }
        return card.chart.first { Calendar.current.isDate($0.day, inSameDayAs: rawSelection) }
    }

    /// Line segments restart after each gap so a missing day is never bridged.
    private var segments: [Date: Int] {
        var result: [Date: Int] = [:]
        var segment = 0
        for point in card.chart {
            if point.value == nil { segment += 1 } else { result[point.day] = segment }
        }
        return result
    }

    var body: some View {
        let segments = segments
        let selected = selected
        let domain = yDomain
        Chart {
            ForEach(card.chart) { point in
                if let value = point.value {
                    valueMarks(point, value: hasAppeared ? value : domain.lowerBound, floor: domain.lowerBound,
                               segment: segments[point.day] ?? 0, dimmed: selected != nil && selected?.day != point.day)
                } else {
                    // Explicit "no data" column so a gap never reads as a low day.
                    RectangleMark(x: .value("Day", point.day, unit: .day))
                        .foregroundStyle(.gray.opacity(selected?.day == point.day ? 0.3 : 0.14))
                        .clipShape(.rect(cornerRadius: isDense ? 1 : 4))
                        .accessibilityLabel(point.accessibilityLabel)
                        .accessibilityValue(point.accessibilityValue)
                }
            }

            if isFull, selected == nil, let average = card.averageLine, let label = card.averageLabel {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(card.metric.tint.opacity(0.7))
                    .zIndex(1)
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(card.metric.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 5))
                    }
                    .accessibilityHidden(true)
            }
            // Labeled in the legend under the chart so it never collides with bars.
            if isFull, let target = card.targetLine {
                RuleMark(y: .value("Goal", target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))
                    .foregroundStyle(Color.secondary)
                    .accessibilityHidden(true)
            }

            if let selected {
                RuleMark(x: .value("Day", selected.day, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .zIndex(-1)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Callout(point: selected, tint: card.metric.tint)
                    }
                    .accessibilityHidden(true)
            }
        }
        .chartOverlay { proxy in
            if isFull {
                GeometryReader { geometry in
                    let originX = proxy.plotFrame.map { geometry[$0].origin.x } ?? 0
                    Rectangle()
                        .fill(.clear)
                        .contentShape(.rect)
                        // Tap selects a day and keeps it; tap it again to clear.
                        .onTapGesture { location in
                            let day = proxy.value(atX: location.x - originX, as: Date.self)
                            withAnimation(.snappy) {
                                rawSelection = day.flatMap { day in
                                    selected.map { Calendar.current.isDate($0.day, inSameDayAs: day) } == true ? nil : day
                                }
                            }
                        }
                        // Press and hold, then drag, to scrub. The hold keeps vertical
                        // scrolling working when a drag starts on the chart.
                        .gesture(
                            LongPressGesture(minimumDuration: 0.2)
                                .sequenced(before: DragGesture(minimumDistance: 0))
                                .onChanged { value in
                                    if case .second(true, let drag?) = value {
                                        rawSelection = proxy.value(atX: drag.location.x - originX, as: Date.self)
                                    }
                                }
                        )
                }
            }
        }
        .chartXAxis {
            if isFull {
                AxisMarks(values: .automatic(desiredCount: isDense ? 4 : 5)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: !isDense)
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .chartYAxis {
            if isFull {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                    AxisValueLabel().font(.caption2).foregroundStyle(Color.secondary)
                }
            }
        }
        .chartYScale(domain: domain)
        .padding(.top, isFull ? 36 : 0) // room for the callout above the plot
        .sensoryFeedback(.selection, trigger: selected?.day)
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.15)) { hasAppeared = true }
        }
        .onChange(of: card.chart) { _, _ in
            rawSelection = nil
        }
    }

    /// Zero-based for totals; for resting HR, padded so a 2 bpm wobble
    /// doesn't fill the chart and look dramatic.
    private var yDomain: ClosedRange<Double> {
        let values = card.chart.compactMap(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        if card.chartIncludesZero { return 0...max(1, max(high, card.targetLine ?? 0)) * 1.15 }
        return (low - 8)...(high + 8)
    }

    @ChartContentBuilder
    private func valueMarks(
        _ point: MetricCardState.ChartPoint, value: Double, floor: Double, segment: Int, dimmed: Bool
    ) -> some ChartContent {
        let tint = card.metric.tint
        let opacity = dimmed ? 0.3 : (point.isPartial ? 0.45 : 1)
        if card.metric == .restingHeartRate {
            AreaMark(
                x: .value("Day", point.day, unit: .day),
                yStart: .value("Floor", floor),
                yEnd: .value(card.metric.unit, value),
                series: .value("Segment", segment)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            .accessibilityHidden(true)
            LineMark(x: .value("Day", point.day, unit: .day), y: .value(card.metric.unit, value), series: .value("Segment", segment))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: isFull ? 2.5 : 1.75, lineCap: .round, lineJoin: .round))
                .accessibilityLabel(point.accessibilityLabel)
                .accessibilityValue(point.accessibilityValue)
            if isFull && (!isDense || !dimmed && rawSelection != nil) {
                PointMark(x: .value("Day", point.day, unit: .day), y: .value(card.metric.unit, value))
                    .symbolSize(rawSelection != nil && !dimmed ? 90 : 28)
                    .foregroundStyle(tint.opacity(point.isPartial ? 0.45 : 1))
                    .symbol { Circle().fill(tint).overlay(Circle().stroke(.background, lineWidth: 2)) }
                    .accessibilityHidden(true)
            }
        } else {
            BarMark(x: .value("Day", point.day, unit: .day), y: .value(card.metric.unit, value))
                .foregroundStyle(LinearGradient(colors: [tint, tint.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                .opacity(opacity)
                .clipShape(.rect(cornerRadius: isDense ? 1.5 : (isFull ? 6 : 3)))
                .accessibilityLabel(point.accessibilityLabel)
                .accessibilityValue(point.accessibilityValue)
        }
    }
}

/// Floating glass callout shown while scrubbing.
private struct Callout: View {
    let point: MetricCardState.ChartPoint
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.calloutDate)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(point.accessibilityValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(point.value == nil ? .secondary : tint)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.background, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.25)))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}
