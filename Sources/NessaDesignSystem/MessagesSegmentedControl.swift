import SwiftUI
#if os(iOS)
  import UIKit
#endif

/// Native segmented selection with a comfortable height and system appearance.
public struct MessagesSegmentedControl: View {
  public let labels: [String]
  public let accessibilityLabel: String
  @Binding public var selectedIndex: Int
  public init(labels: [String], selectedIndex: Binding<Int>, accessibilityLabel: String = "Selection") {
    self.labels = labels
    self.accessibilityLabel = accessibilityLabel
    self._selectedIndex = selectedIndex
  }
  public var body: some View {
    #if os(iOS)
      NativeSegments(labels: labels, selectedIndex: $selectedIndex)
        .frame(height: AgentDetailsStyle.tabHeight)
        .accessibilityRepresentation {
          Picker(accessibilityLabel, selection: $selectedIndex) {
            ForEach(labels.indices, id: \.self) { index in Text(labels[index]).tag(index) }
          }.pickerStyle(.segmented)
        }
    #else
      Picker(accessibilityLabel, selection: $selectedIndex) {
        ForEach(labels.indices, id: \.self) { index in Text(labels[index]).tag(index) }
      }.pickerStyle(.segmented).frame(minHeight: AgentDetailsStyle.tabHeight)
    #endif
  }
}

#if os(iOS)
  private struct NativeSegments: UIViewRepresentable {
    let labels: [String]
    @Binding var selectedIndex: Int
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> UISegmentedControl {
      let control = UISegmentedControl(items: labels)
      control.addTarget(context.coordinator, action: #selector(Coordinator.select(_:)), for: .valueChanged)
      return control
    }
    func updateUIView(_ control: UISegmentedControl, context: Context) {
      context.coordinator.parent = self
      if (0..<control.numberOfSegments).map({ control.titleForSegment(at: $0) ?? "" }) != labels {
        control.removeAllSegments()
        for (index, label) in labels.enumerated() {
          control.insertSegment(withTitle: label, at: index, animated: false)
        }
      }
      control.selectedSegmentIndex = selectedIndex
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
      CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: AgentDetailsStyle.tabHeight)
    }
    final class Coordinator: NSObject {
      var parent: NativeSegments
      init(parent: NativeSegments) { self.parent = parent }
      @objc func select(_ control: UISegmentedControl) {
        guard parent.labels.indices.contains(control.selectedSegmentIndex) else { return }
        parent.selectedIndex = control.selectedSegmentIndex
      }
    }
  }
#endif
