import SwiftUI

// MARK: - M-19 滑动操作（系统 List + swipeActions）
//
// §5.2 / §5.0 裁决：交给系统 swipeActions，不自建拖拽容器。因此：
// · 实际触发距离由系统决定，不硬编码 76pt（VERIFY-04 已登记，差异待真机体感复核）；
// · 「同一时间只展开一行」由系统 List 保证，不再引入 openRow 单例；
// · 按钮宽度 64 + 间隔 8 是上游视觉规格，系统按钮宽度由系统决定，仅保留动作集合与顺序；
// · 动作语义完整保留：右滑完成/恢复，左滑推迟或跳过、放弃（仅未完成的一次性任务）、删除。
// · iOS 27 起可通过 onPresentationChanged 感知展开，用于把展开中的行染成灰色。

extension View {
    @ViewBuilder
    func taskRowSwipeActions(
        model: TaskRowModel,
        lang: String,
        postponeEnabled: Bool = true,
        onSwipePresentation: ((HorizontalEdge, Bool) -> Void)? = nil,
        onComplete: @escaping () -> Void,
        onPostpone: @escaping () -> Void,
        onDrop: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        if #available(iOS 27.0, *), let onSwipePresentation {
            self
                .swipeActions(
                    edge: .leading, allowsFullSwipe: true,
                    content: {
                        leadingActions(model: model, lang: lang, onComplete: onComplete)
                    },
                    onPresentationChanged: { onSwipePresentation(.leading, $0) }
                )
                .swipeActions(
                    edge: .trailing, allowsFullSwipe: false,
                    content: {
                        trailingActions(
                            model: model, lang: lang, postponeEnabled: postponeEnabled,
                            onPostpone: onPostpone, onDrop: onDrop, onDelete: onDelete
                        )
                    },
                    onPresentationChanged: { onSwipePresentation(.trailing, $0) }
                )
        } else {
            self
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    leadingActions(model: model, lang: lang, onComplete: onComplete)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    trailingActions(
                        model: model, lang: lang, postponeEnabled: postponeEnabled,
                        onPostpone: onPostpone, onDrop: onDrop, onDelete: onDelete
                    )
                }
        }
    }

    @ViewBuilder
    private func leadingActions(
        model: TaskRowModel, lang: String, onComplete: @escaping () -> Void
    ) -> some View {
        let title = model.task.dropped
            ? AppStrings.t("恢复", lang: lang)
            : model.isDone ? AppStrings.t("未完成", lang: lang) : AppStrings.t("完成", lang: lang)
        Button(action: onComplete) {
            Label {
                Text(title)
            } icon: {
                Image(model.task.done ? "icon-x" : "icon-check")
                    .renderingMode(.template)
            }
        }
        .tint(model.task.done ? .gray : .green)
    }

    // 声明顺序：删除在最外（最右），与上游「推迟、放弃、删除」从左到右一致。
    @ViewBuilder
    private func trailingActions(
        model: TaskRowModel, lang: String, postponeEnabled: Bool,
        onPostpone: @escaping () -> Void,
        onDrop: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        let canDrop = TaskRowContract.canDrop(
            postpone: postponeEnabled,
            repeatRule: model.task.repeatRule,
            done: model.isDone
        )
        let postpone = TaskRowContract.postponeAction(repeatRule: model.task.repeatRule)

        Button(role: .destructive, action: onDelete) {
            Label {
                Text(AppStrings.t("删除", lang: lang))
            } icon: {
                Image("icon-trash").renderingMode(.template)
            }
        }
        if canDrop {
            Button(action: onDrop) {
                Label {
                    Text(AppStrings.t("放弃", lang: lang))
                } icon: {
                    Image("icon-ban").renderingMode(.template)
                }
            }
            .tint(.gray)
        }
        if postponeEnabled {
            Button(action: onPostpone) {
                Label {
                    Text(AppStrings.t(postpone.key, lang: lang))
                } icon: {
                    Image(DesignContract.assetName(postpone.icon)).renderingMode(.template)
                }
            }
            .tint(.orange)
        }
    }
}
