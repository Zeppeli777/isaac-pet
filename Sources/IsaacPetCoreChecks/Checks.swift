import CoreGraphics
import Foundation
import IsaacPetCore

@main
enum IsaacPetCoreChecks {
    @MainActor
    static func main() async {
        var failures: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        check(AnimationCatalog.cellWidth * AnimationCatalog.columns == 1536, "atlas width contract")
        check(AnimationCatalog.cellHeight * AnimationCatalog.rows == 2288, "atlas height contract")
        check(AnimationCatalog.specs.count == AnimationID.allCases.count, "every animation has a spec")
        check(AnimationCatalog.spec(for: .walkRight).frameCount == 8, "walk frame count")
        check(AnimationCatalog.spec(for: .idle).frameCount == 7, "idle frame count")
        check(AnimationCatalog.verticalWalkingColumns == 4, "vertical walking columns")
        check(AnimationCatalog.verticalWalkingRows == 2, "vertical walking rows")
        check(AnimationCatalog.verticalWalkingSpecs.count == VerticalWalkingDirection.allCases.count, "vertical walking specifications")
        check(AnimationCatalog.verticalWalkingSpec(for: .down).row == 0, "down walking atlas row")
        check(AnimationCatalog.verticalWalkingSpec(for: .up).row == 1, "up walking atlas row")
        check(AnimationCatalog.verticalWalkingSpec(for: .down).frameCount == 4, "down walking frame count")
        check(AnimationCatalog.verticalWalkingSpec(for: .up).loops, "up walking loops")

        let looping = AnimationCatalog.spec(for: .walkRight)
        check(looping.frameIndex(elapsed: 0) == 0, "loop begins at frame zero")
        check(looping.frameIndex(elapsed: looping.duration) == 0, "loop wraps")
        let oneShot = AnimationCatalog.spec(for: .jump)
        check(oneShot.frameIndex(elapsed: oneShot.duration * 2) == oneShot.frameCount - 1, "one-shot clamps")

        check(Direction8.from(deltaX: 0, deltaY: 100) == .up, "up direction")
        check(Direction8.from(deltaX: 100, deltaY: 100) == .upRight, "up-right direction")
        check(Direction8.from(deltaX: 100, deltaY: 0) == .right, "right direction")
        check(Direction8.from(deltaX: 100, deltaY: -100) == .downRight, "down-right direction")
        check(Direction8.from(deltaX: 0, deltaY: -100) == .down, "down direction")
        check(Direction8.from(deltaX: -100, deltaY: -100) == .downLeft, "down-left direction")
        check(Direction8.from(deltaX: -100, deltaY: 0) == .left, "left direction")
        check(Direction8.from(deltaX: -100, deltaY: 100) == .upLeft, "up-left direction")
        check(Direction8.from(deltaX: 10, deltaY: 10) == nil, "pointer dead zone")

        let upCell = AnimationCatalog.atlasCell(for: .up)
        let rightCell = AnimationCatalog.atlasCell(for: .right)
        let downCell = AnimationCatalog.atlasCell(for: .down)
        let leftCell = AnimationCatalog.atlasCell(for: .left)
        check(upCell.row == 9 && upCell.column == 0, "up atlas cell")
        check(rightCell.row == 9 && rightCell.column == 4, "right atlas cell")
        check(downCell.row == 10 && downCell.column == 0, "down atlas cell")
        check(leftCell.row == 10 && leftCell.column == 4, "left atlas cell")
        check(AnimationCatalog.shootingColumn(for: .up) == 0, "up shooting pose")
        check(AnimationCatalog.shootingColumn(for: .right) == 1, "right shooting pose")
        check(AnimationCatalog.shootingColumn(for: .down) == 2, "down shooting pose")
        check(AnimationCatalog.shootingColumn(for: .left) == 3, "left shooting pose")
        check(AnimationCatalog.shootingColumn(for: .upRight) == 1, "diagonal shooting uses side pose")
        check(AnimationCatalog.shootingColumn(for: .downLeft) == 3, "mirrored diagonal shooting pose")

        check(PetState.dragging.priority > PetState.action(.jump).priority, "drag priority")
        check(PetState.dragging.priority > PetState.playing(.down, moving: true).priority, "play drag priority")
        check(PetState.playing(.down, moving: true).priority > PetState.action(.jump).priority, "play priority")
        check(PetState.action(.jump).priority > PetState.walking(.right).priority, "action priority")
        check(PetState.walking(.right).priority > PetState.tracking(.up).priority, "walking priority")
        check(PetState.tracking(.up).priority > PetState.idle.priority, "tracking priority")

        let screen = ScreenBounds(rect: CGRect(x: -100, y: 20, width: 1000, height: 700))
        let petSize = CGSize(width: 200, height: 220)
        check(
            screen.clampedOrigin(CGPoint(x: -500, y: 999), petSize: petSize) == CGPoint(x: -100, y: 24),
            "left screen clamp"
        )
        check(
            screen.clampedOrigin(CGPoint(x: 999, y: -50), petSize: petSize) == CGPoint(x: 700, y: 24),
            "right screen clamp"
        )
        let origin = screen.origin(horizontalPosition: 0.25, petSize: petSize)
        check(origin == CGPoint(x: 100, y: 24), "normalized position restore")
        check(abs(screen.horizontalPosition(for: origin, petSize: petSize) - 0.25) < 0.0001, "position persistence")
        check(
            screen.clampedFreeOrigin(CGPoint(x: -500, y: 999), petSize: petSize) == CGPoint(x: -96, y: 496),
            "free movement screen clamp"
        )

        check(PlayKey(rawValue: 13) == .moveUp, "W key mapping")
        check(PlayKey(rawValue: 123) == .shootLeft, "left arrow mapping")
        let diagonalMovement = PlayInput.movementVector(for: [.moveUp, .moveRight])
        check(abs(hypot(diagonalMovement.dx, diagonalMovement.dy) - 1) < 0.0001, "diagonal movement normalized")
        check(diagonalMovement.dx > 0 && diagonalMovement.dy > 0, "diagonal movement signs")
        check(PlayInput.movementVector(for: [.moveLeft, .moveRight]) == .zero, "opposite movement cancels")
        check(PlayInput.walkingDirection(for: CGVector(dx: 0, dy: 1)) == .up, "W uses up walking")
        check(PlayInput.walkingDirection(for: CGVector(dx: 0, dy: -1)) == .down, "S uses down walking")
        check(PlayInput.walkingDirection(for: CGVector(dx: -1, dy: 0)) == .left, "A keeps left walking")
        check(PlayInput.walkingDirection(for: CGVector(dx: 1, dy: 0)) == .right, "D keeps right walking")
        check(PlayInput.walkingDirection(for: CGVector(dx: 0.3, dy: 0.8)) == .up, "vertical dominant diagonal gait")
        check(PlayInput.walkingDirection(for: diagonalMovement) == .right, "equal diagonal keeps horizontal gait")
        check(PlayWalkingDirection.up.verticalDirection == .up, "up vertical atlas mapping")
        check(PlayWalkingDirection.down.verticalDirection == .down, "down vertical atlas mapping")
        check(PlayWalkingDirection.left.verticalDirection == nil, "horizontal has no vertical atlas mapping")
        check(PlayInput.firingDirection(for: [.shootUp, .shootRight]) == .upRight, "diagonal firing")
        check(PlayInput.firingDirection(for: [.shootUp, .shootDown]) == nil, "opposite firing cancels")
        let shotVector = PlayInput.unitVector(for: .downLeft)
        check(abs(hypot(shotVector.dx, shotVector.dy) - 1) < 0.0001, "shot vector normalized")

        check(PetSettings(scale: 0.8).scale == 0.75, "scale snaps down")
        check(PetSettings(scale: 1.12).scale == 1, "scale snaps to normal")
        check(PetSettings(horizontalPosition: 2).horizontalPosition == 1, "position upper clamp")
        check(PetSettings(horizontalPosition: -1).horizontalPosition == 0, "position lower clamp")

        check(SpeechBubblePolicy.normalized("  嗨！\nIsaac  ") == "嗨！ Isaac", "speech whitespace normalization")
        check(SpeechBubblePolicy.normalized(" \n\t ") == nil, "empty speech is rejected")
        let longSpeech = String(repeating: "a", count: 100)
        check(SpeechBubblePolicy.normalized(longSpeech)?.count == 80, "speech length cap")
        check(SpeechBubblePolicy.normalized(longSpeech)?.hasSuffix("…") == true, "speech truncation marker")
        check(SpeechBubblePolicy.displayDuration(for: "hi") == 3.11, "short speech duration")
        check(SpeechBubblePolicy.displayDuration(for: longSpeech) == 8, "speech duration cap")

        check(TarotDeck.majorArcana.count == 22, "major arcana has 22 cards")
        check(Set(TarotDeck.majorArcana.map(\.id)).count == 22, "major arcana IDs are unique")
        check(TarotDeck.majorArcana.first?.name.contains("愚者") == true, "major arcana starts with The Fool")
        check(TarotDeck.majorArcana.last?.name.contains("世界") == true, "major arcana ends with The World")
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let tarotDayOne = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 UTC
        let tarotDayTwo = tarotDayOne.addingTimeInterval(86_400)
        check(
            TarotDrawPolicy.dailyCard(for: tarotDayOne, calendar: utcCalendar).id == 0,
            "daily tarot starts at a stable reference card"
        )
        check(
            TarotDrawPolicy.dailyCard(for: tarotDayTwo, calendar: utcCalendar).id == 1,
            "daily tarot advances by calendar day"
        )
        check(
            TarotDrawPolicy.randomCard(excluding: 0).id != 0,
            "random tarot can exclude the previous card"
        )

        let todoNow = Date(timeIntervalSince1970: 1_000)
        let earlyTodo = TodoItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "  写完\n报告  ",
            createdAt: todoNow,
            dueAt: todoNow.addingTimeInterval(60)
        )
        let laterTodo = TodoItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "整理资料",
            createdAt: todoNow.addingTimeInterval(1),
            dueAt: todoNow.addingTimeInterval(120)
        )
        let undatedTodo = TodoItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            title: "随手记",
            createdAt: todoNow.addingTimeInterval(2)
        )
        let completedTodo = TodoItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            title: "已完成",
            createdAt: todoNow.addingTimeInterval(3),
            completedAt: todoNow
        )
        check(earlyTodo.title == "写完 报告", "todo title normalization")
        check(TodoPolicy.normalizedTitle(" \n ") == nil, "empty todo title rejected")
        check(TodoPolicy.sorted([completedTodo, undatedTodo, laterTodo, earlyTodo]).map(\.id) == [
            earlyTodo.id, laterTodo.id, undatedTodo.id, completedTodo.id,
        ], "todo ordering")
        check(TodoPolicy.nextPending(in: [undatedTodo, laterTodo])?.id == laterTodo.id, "next pending todo")
        check(
            TodoPolicy.dueForDelivery(in: [earlyTodo, laterTodo], at: todoNow.addingTimeInterval(90)).map(\.id)
                == [earlyTodo.id],
            "due todo delivery"
        )
        var remindedTodo = earlyTodo
        remindedTodo.remindedAt = todoNow
        check(
            TodoPolicy.dueForDelivery(in: [remindedTodo], at: todoNow.addingTimeInterval(90)).isEmpty,
            "delivered todo does not repeat"
        )
        do {
            let encodedTodos = try TodoFileCodec.encode([completedTodo, earlyTodo])
            let decodedTodos = try TodoFileCodec.decode(encodedTodos)
            check(decodedTodos == [earlyTodo, completedTodo], "todo JSON round trip and ordering")
        } catch {
            failures.append("todo JSON codec: \(error)")
        }
        do {
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("IsaacPetCoreChecks-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
            let fileURL = temporaryDirectory.appendingPathComponent("todos.json")
            let store = try TodoStore(fileURL: fileURL)
            let saved = try store.add(title: " 持久化 Todo ", dueAt: todoNow.addingTimeInterval(60))
            try store.toggleCompleted(id: saved.id, at: todoNow)
            let reloaded = try TodoStore(fileURL: fileURL)
            check(reloaded.items.count == 1, "todo store reload count")
            check(reloaded.items.first?.title == "持久化 Todo", "todo store reload title")
            check(reloaded.items.first?.completedAt == todoNow, "todo store reload completion")
            try reloaded.remove(id: saved.id)
            let afterDeletion = try TodoStore(fileURL: fileURL)
            check(afterDeletion.items.isEmpty, "todo store deletion persistence")

            let overdueCompleted = TodoItem(
                title: "恢复的逾期任务",
                createdAt: todoNow,
                dueAt: todoNow.addingTimeInterval(-60),
                completedAt: todoNow,
                remindedAt: todoNow
            )
            try TodoFileCodec.encode([overdueCompleted]).write(to: fileURL, options: .atomic)
            let restoredStore = try TodoStore(fileURL: fileURL)
            _ = try restoredStore.toggleCompleted(id: overdueCompleted.id, at: todoNow.addingTimeInterval(1))
            check(
                restoredStore.items.first?.remindedAt == nil,
                "restored overdue todo becomes eligible for a new reminder"
            )
        } catch {
            failures.append("todo store persistence: \(error)")
        }
        do {
            let source = TodoExternalSource(
                kind: .appleReminders,
                itemIdentifier: "reminder-1",
                containerIdentifier: "list-1",
                containerTitle: "工作",
                lastSyncedAt: todoNow
            )
            let firstRecord = ExternalTodoRecord(
                source: source,
                title: "系统任务",
                dueAt: todoNow.addingTimeInterval(300),
                completedAt: nil
            )
            let firstMerge = TodoPolicy.merging([firstRecord], into: [], now: todoNow)
            check(firstMerge.summary == TodoImportSummary(inserted: 1, updated: 0, skipped: 0), "external todo insert summary")
            check(firstMerge.items.first?.externalSource?.itemIdentifier == "reminder-1", "external todo source mapping")

            let changedRecord = ExternalTodoRecord(
                source: source,
                title: "系统任务（更新）",
                dueAt: todoNow.addingTimeInterval(600),
                completedAt: todoNow.addingTimeInterval(30)
            )
            let secondMerge = TodoPolicy.merging([changedRecord], into: firstMerge.items, now: todoNow.addingTimeInterval(60))
            check(secondMerge.summary == TodoImportSummary(inserted: 0, updated: 1, skipped: 0), "external todo update summary")
            check(secondMerge.items.count == 1, "external todo stable identifier deduplication")
            check(secondMerge.items.first?.title == "系统任务（更新）", "external todo title refresh")
            check(secondMerge.items.first?.isCompleted == true, "external todo completion refresh")

            var previouslyReminded = secondMerge.items.first!
            previouslyReminded.remindedAt = todoNow
            let reopenedRecord = ExternalTodoRecord(
                source: source,
                title: "系统任务（更新）",
                dueAt: changedRecord.dueAt,
                completedAt: nil
            )
            let reopenedMerge = TodoPolicy.merging(
                [reopenedRecord],
                into: [previouslyReminded],
                now: todoNow.addingTimeInterval(90)
            )
            check(
                reopenedMerge.items.first?.remindedAt == nil,
                "reopened external todo becomes eligible for a new reminder"
            )

            let oldJSON = """
            [{"id":"00000000-0000-0000-0000-000000000009","title":"旧数据","createdAt":"1970-01-01T00:16:40Z"}]
            """.data(using: .utf8)!
            let oldItems = try TodoFileCodec.decode(oldJSON)
            check(oldItems.first?.externalSource == nil, "old todo JSON remains compatible")
        } catch {
            failures.append("external todo merge: \(error)")
        }
        do {
            let notionJSON = """
            {
              "results": [
                {
                  "id": "page-open",
                  "archived": false,
                  "in_trash": false,
                  "last_edited_time": "1970-01-01T00:16:40Z",
                  "properties": {
                    "任务": {"type":"title","title":[{"plain_text":"Notion 任务"}]},
                    "截止日期": {"type":"date","date":{"start":"2026-08-12"}},
                    "完成": {"type":"checkbox","checkbox":false}
                  }
                },
                {
                  "id": "page-done",
                  "archived": false,
                  "in_trash": false,
                  "last_edited_time": "1970-01-01T00:18:20Z",
                  "properties": {
                    "Name": {"type":"title","title":[{"plain_text":"Done item"}]},
                    "Status": {"type":"status","status":{"name":"Done"}}
                  }
                }
              ],
              "next_cursor": "cursor-2",
              "has_more": true
            }
            """.data(using: .utf8)!
            let firstPage = try NotionPayloadDecoder.decode(
                notionJSON,
                dataSourceIdentifier: "source-1",
                knownItemIdentifiers: [],
                syncDate: todoNow
            )
            check(firstPage.records.count == 1, "notion skips unlinked completed history")
            check(firstPage.records.first?.title == "Notion 任务", "notion title mapping")
            check(firstPage.records.first?.dueAt != nil, "notion date mapping")
            check(firstPage.nextCursor == "cursor-2" && firstPage.hasMore, "notion pagination mapping")

            let linkedPage = try NotionPayloadDecoder.decode(
                notionJSON,
                dataSourceIdentifier: "source-1",
                knownItemIdentifiers: ["page-done"],
                syncDate: todoNow
            )
            check(linkedPage.records.count == 2, "notion refreshes linked completion")
            check(linkedPage.records.first(where: { $0.source.itemIdentifier == "page-done" })?.completedAt != nil, "notion status completion mapping")
            check(
                NotionDataSourceIdentifier.normalized("https://notion.so/aabbccddeeff00112233445566778899?v=1")
                    == "aabbccdd-eeff-0011-2233-445566778899",
                "notion data source URL normalization"
            )
            check(
                NotionDataSourceIdentifier.normalized("aabbccdd-eeff-0011-2233-445566778899")
                    == "aabbccdd-eeff-0011-2233-445566778899",
                "notion UUID normalization"
            )
            check(NotionDataSourceIdentifier.normalized("not-an-id") == nil, "notion invalid identifier rejected")
        } catch {
            failures.append("notion payload decoder: \(error)")
        }

        let isaacAgent = AgentCatalog.profile(for: .isaac)
        let magdaleneAgent = AgentCatalog.profile(for: .magdalene)
        let cainAgent = AgentCatalog.profile(for: .cain)
        let judasAgent = AgentCatalog.profile(for: .judas)
        check(
            AgentExecutionPolicy.authorization(for: .readLocalTodos, role: isaacAgent) == .automatic,
            "local todo reading is automatic for Isaac"
        )
        check(
            AgentExecutionPolicy.authorization(for: .writeLocalTodos, role: judasAgent) == .requiresConfirmation,
            "local todo writes require confirmation"
        )
        check(
            AgentExecutionPolicy.authorization(for: .readLocalTodos, role: magdaleneAgent) == .automatic,
            "local todo reading is automatic for Magdalene"
        )
        check(
            AgentExecutionPolicy.authorization(for: .networkResearch, role: cainAgent) == .unavailable,
            "network research unavailable without installed adapter"
        )
        check(
            AgentExecutionPolicy.authorization(for: .runCommands, role: isaacAgent) == .unavailable,
            "undeclared command execution unavailable"
        )
        check(
            AgentExecutionPolicy.authorization(for: .focusTimer, role: judasAgent) == .automatic,
            "local focus timer is automatic for Judas"
        )
        check(
            AgentExecutionPolicy.authorization(for: .focusTimer, role: isaacAgent) == .unavailable,
            "focus timer is not available to undeclared roles"
        )
        check(AgentTaskStatus.queued.allowsTransition(to: .awaitingConfirmation), "queued task can await confirmation")
        check(AgentTaskStatus.awaitingConfirmation.allowsTransition(to: .succeeded), "confirmed task can succeed")
        check(!AgentTaskStatus.queued.allowsTransition(to: .succeeded), "queued task cannot bypass execution")
        check(!AgentTaskStatus.succeeded.allowsTransition(to: .running), "terminal task cannot restart")
        check(AgentTaskStatus.cancelled.isTerminal, "cancelled task is terminal")
        check(
            FocusSessionPolicy.duration(from: "999999") == FocusSessionPolicy.maximumDuration,
            "focus duration is capped"
        )
        check(
            FocusSessionPolicy.duration(from: "bad") == FocusSessionPolicy.defaultDuration,
            "invalid focus duration uses default"
        )
        let focusNow = Date(timeIntervalSince1970: 1_800_000_000)
        let focusDeadline = focusNow.addingTimeInterval(61.2)
        check(
            FocusSessionPolicy.remainingSeconds(until: focusDeadline, now: focusNow) == 62,
            "focus countdown rounds up remaining seconds"
        )
        check(
            FocusSessionPolicy.clockText(remainingSeconds: 125) == "02:05",
            "focus countdown clock formatting"
        )
        let cancellableFocus = Task {
            try await FocusSessionTimer.wait(until: Date().addingTimeInterval(30))
        }
        cancellableFocus.cancel()
        do {
            try await cancellableFocus.value
            failures.append("focus countdown cancellation")
        } catch is CancellationError {
            // Expected: cancellation must interrupt a long local focus timer immediately.
        } catch {
            failures.append("focus countdown cancellation: \(error)")
        }

        let planningNow = Date(timeIntervalSince1970: 1_800_000_000)
        let planningCalendar = Calendar(identifier: .gregorian)
        let overduePlanTodo = TodoItem(
            title: "补交报告",
            createdAt: planningNow.addingTimeInterval(-1000),
            dueAt: planningNow.addingTimeInterval(-60)
        )
        let todayPlanTodo = TodoItem(
            title: "今天开会",
            createdAt: planningNow.addingTimeInterval(-900),
            dueAt: planningNow.addingTimeInterval(60)
        )
        let undatedPlanTodo = TodoItem(
            title: "整理书桌",
            createdAt: planningNow.addingTimeInterval(-800)
        )
        let dailyPlan = LocalPlanningAgent.makeDailyPlan(
            from: [undatedPlanTodo, todayPlanTodo, overduePlanTodo],
            now: planningNow,
            calendar: planningCalendar
        )
        check(dailyPlan.headline.contains("逾期"), "daily plan highlights overdue tasks")
        check(dailyPlan.sourceTodoIDs.first == overduePlanTodo.id, "daily plan prioritizes overdue task")
        check(dailyPlan.steps.count == 3, "daily plan selects actionable tasks")
        check(
            LocalPlanningAgent.makeDailyPlan(from: [], now: planningNow).sourceTodoIDs.isEmpty,
            "empty daily plan has no source todo"
        )

        let wellbeingPlan = LocalWellbeingAgent.makeRhythmCheck(
            from: [undatedPlanTodo, todayPlanTodo, overduePlanTodo],
            now: planningNow,
            calendar: planningCalendar
        )
        check(wellbeingPlan.headline.contains("逾期"), "wellbeing plan notices overdue workload")
        check(wellbeingPlan.workloadCount == 3, "wellbeing plan counts pending todos")
        check(
            wellbeingPlan.suggestions.contains(where: { $0.contains("喝水") }),
            "wellbeing plan includes a concrete break suggestion"
        )
        let emptyWellbeingPlan = LocalWellbeingAgent.makeRhythmCheck(from: [], now: planningNow)
        check(emptyWellbeingPlan.workloadCount == 0, "empty wellbeing plan reports light workload")

        do {
            let request = OpenAIResponsesRequest(
                model: "gpt-test",
                instructions: "short",
                input: "hello",
                maxOutputTokens: 8,
                store: false
            )
            let requestObject = try JSONSerialization.jsonObject(
                with: OpenAIResponsesCodec.encodeRequest(request)
            ) as? [String: Any]
            check(requestObject?["model"] as? String == "gpt-test", "LLM request model encoding")
            check(requestObject?["max_output_tokens"] as? Int == 16, "LLM output token lower bound")
            check(requestObject?["store"] as? Bool == false, "LLM responses are not stored by request")

            let responseJSON = """
            {
              "output": [
                {"type":"reasoning","content":[]},
                {"type":"message","content":[
                  {"type":"output_text","text":"第一句"},
                  {"type":"refusal","text":"忽略"},
                  {"type":"output_text","text":"第二句"}
                ]}
              ]
            }
            """
            let decodedLLMText = try OpenAIResponsesCodec.decodeText(from: Data(responseJSON.utf8))
            check(decodedLLMText == "第一句\n第二句", "LLM decoder collects all output_text items")
            let errorJSON = #"{"error":{"message":"bad key"}}"#
            check(
                OpenAIResponsesCodec.decodeAPIError(from: Data(errorJSON.utf8), statusCode: 401) == "bad key",
                "LLM API error decoding"
            )
        } catch {
            failures.append("LLM request and response codec: \(error)")
        }

        do {
            let temporaryAgents = FileManager.default.temporaryDirectory
                .appendingPathComponent("IsaacAgentChecks-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: temporaryAgents) }
            let auditStore = try AgentAuditStore(directoryURL: temporaryAgents)
            let task = try auditStore.createTask(
                roleID: .isaac,
                capability: .readLocalTodos,
                title: "生成今日计划",
                at: planningNow
            )
            try auditStore.transition(
                taskID: task.id,
                to: .running,
                summary: "开始读取本地 Todo",
                at: planningNow.addingTimeInterval(1)
            )
            try auditStore.transition(
                taskID: task.id,
                to: .succeeded,
                summary: "计划已生成",
                at: planningNow.addingTimeInterval(2)
            )
            let reloadedAudit = try AgentAuditStore(directoryURL: temporaryAgents)
            check(reloadedAudit.tasks.first?.status == .succeeded, "agent task persistence")
            check(reloadedAudit.events.map(\.status).prefix(3) == [.succeeded, .running, .queued], "agent audit order")
            check(reloadedAudit.events.allSatisfy { $0.taskID == task.id }, "agent audit task linkage")

            let focusDeadline = planningNow.addingTimeInterval(1_500)
            let focusTask = try auditStore.createTask(
                roleID: .judas,
                capability: .focusTimer,
                title: "专注 25 分钟",
                deadlineAt: focusDeadline,
                subject: "写报告",
                at: planningNow
            )
            check(reloadedAudit.tasks.first?.deadlineAt == nil, "legacy task has no focus deadline")
            try auditStore.transition(
                taskID: focusTask.id,
                to: .running,
                summary: "开始专注",
                at: planningNow.addingTimeInterval(1)
            )
            let reloadedFocus = try AgentAuditStore(directoryURL: temporaryAgents)
            check(reloadedFocus.tasks.first?.deadlineAt == focusDeadline, "focus deadline persistence")
            check(reloadedFocus.tasks.first?.subject == "写报告", "focus subject persistence")

            let todoProposal = try auditStore.createTask(
                roleID: .judas,
                capability: .writeLocalTodos,
                title: "创建 Todo：整理报告",
                at: planningNow.addingTimeInterval(3)
            )
            try auditStore.transition(
                taskID: todoProposal.id,
                to: .awaitingConfirmation,
                summary: "Judas 请求创建本地 Todo：整理报告",
                at: planningNow.addingTimeInterval(4)
            )
            let awaitingConfirmation = try AgentAuditStore(directoryURL: temporaryAgents)
            check(
                awaitingConfirmation.tasks.first?.status == .awaitingConfirmation,
                "agent write task persists while awaiting confirmation"
            )
            try auditStore.transition(
                taskID: todoProposal.id,
                to: .succeeded,
                summary: "已按用户确认创建本地 Todo：整理报告",
                at: planningNow.addingTimeInterval(5)
            )
            let completedProposal = try AgentAuditStore(directoryURL: temporaryAgents)
            check(
                completedProposal.tasks.first?.status == .succeeded,
                "agent write task persists only after confirmation"
            )
            check(
                completedProposal.events.first(where: { $0.taskID == todoProposal.id })?.status == .succeeded,
                "agent confirmation audit records terminal write status"
            )
            do {
                _ = try auditStore.transition(
                    taskID: todoProposal.id,
                    to: .running,
                    summary: "不应重新运行",
                    at: planningNow.addingTimeInterval(6)
                )
                failures.append("terminal agent task transition should be rejected")
            } catch AgentAuditStoreError.invalidTransition {
                // Expected: task history cannot reopen a terminal write action.
            } catch {
                failures.append("agent transition validation: \(error)")
            }
        } catch {
            failures.append("agent audit persistence: \(error)")
        }

        if failures.isEmpty {
            print("IsaacPetCoreChecks: all checks passed")
        } else {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            exit(1)
        }
    }
}
