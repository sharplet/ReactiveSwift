//
//  FoundationExtensionsSpec.swift
//  ReactiveSwift
//
//  Created by Neil Pankey on 5/22/15.
//  Copyright (c) 2015 GitHub. All rights reserved.
//

import Foundation
import Dispatch
import Result
import Nimble
import Quick
@testable import ReactiveSwift

extension Notification.Name {
	static let racFirst = Notification.Name(rawValue: "rac_notifications_test")
	static let racAnother = Notification.Name(rawValue: "rac_notifications_another")
}

func matchErrorCode<Code: _ErrorCodeProtocol>(_ code: Code) -> Predicate<Error> {
	return Predicate { expression in
		let error = try expression.evaluate()!
		return PredicateResult(
			bool: code ~= error,
			message: .expectedActualValueTo("match error <\(Code._ErrorType(code)._nsError)>")
		)
	}.requireNonNil
}

class FoundationExtensionsSpec: QuickSpec {
	override func spec() {
		describe("NotificationCenter.reactive.notifications") {
			let center = NotificationCenter.default

			it("should send notifications on the signal") {
				let signal = center.reactive.notifications(forName: .racFirst)

				var notif: Notification? = nil
				let disposable = signal.observeValues { notif = $0 }

				center.post(name: .racAnother, object: nil)
				expect(notif).to(beNil())

				center.post(name: .racFirst, object: nil)
				expect(notif?.name) == .racFirst

				notif = nil
				disposable?.dispose()

				center.post(name: .racFirst, object: nil)
				expect(notif).to(beNil())
			}

			it("should be disposed of if it is not reachable and no observer is attached") {
				weak var signal: Signal<Notification, NoError>?
				var isDisposed = false

				let disposable: Disposable? = {
					let innerSignal = center.reactive.notifications(forName: nil)
						.on(disposed: { isDisposed = true })

					signal = innerSignal
					return innerSignal.observe { _ in }
				}()

				expect(isDisposed) == false
				expect(signal).to(beNil())

				disposable?.dispose()

				expect(isDisposed) == true
				expect(signal).to(beNil())
			}

			it("should be not disposed of if it still has one or more active observers") {
				weak var signal: Signal<Notification, NoError>?
				var isDisposed = false

				let disposable: Disposable? = {
					let innerSignal = center.reactive.notifications(forName: nil)
						.on(disposed: { isDisposed = true })

					signal = innerSignal
					innerSignal.observe { _ in }
					return innerSignal.observe { _ in }
				}()

				expect(isDisposed) == false
				expect(signal).to(beNil())

				disposable?.dispose()

				expect(isDisposed) == false
				expect(signal).to(beNil())
			}
		}

		describe("FileHandle.readToEndOfFile") {
			enum TerminalEvent {
				case completed, failed, interrupted
			}

			it("reads a file asynchronously on the main run loop") {
				let file = Bundle(for: FoundationExtensionsSpec.self)
					.url(forResource: "test-file", withExtension: "txt")!
				let handle = try! FileHandle(forReadingFrom: file)

				let contents = handle.reactive.readToEndOfFile(on: .main)
					.filterMap { String(data: $0, encoding: .utf8) }

				var terminalEvent: TerminalEvent?
				var values: [String] = []

				contents.start { event in
					switch event {
					case let .value(value):
						values.append(value)
					case .failed:
						terminalEvent = .failed
					case .completed:
						terminalEvent = .completed
					case .interrupted:
						terminalEvent = .interrupted
					}
				}

				expect(terminalEvent).toEventually(equal(.completed))
				expect(values) == ["Hello, world!\n"]
			}

			it("raises an error if reading fails") {
				let file = Bundle(for: FoundationExtensionsSpec.self)
					.url(forResource: "test-file", withExtension: "txt")!
				let handle = try! FileHandle(forWritingTo: file)

				let contents = handle.reactive.readToEndOfFile(on: .main)
					.filterMap { String(data: $0, encoding: .utf8) }

				var error: Error?
				var terminalEvent: TerminalEvent?
				var values: [String] = []

				contents.start { event in
					switch event {
					case let .value(value):
						values.append(value)
					case let .failed(anyError):
						error = anyError.error
						terminalEvent = .failed
					case .completed:
						terminalEvent = .completed
					case .interrupted:
						terminalEvent = .interrupted
					}
				}

				expect(terminalEvent).toEventually(equal(.failed))
				expect(error).to(matchErrorCode(POSIXError.ENOMEM))
				expect(values) == []
			}
		}

		describe("DispatchTimeInterval") {
			it("should scale time values as expected") {
				expect((DispatchTimeInterval.seconds(1) * 0.1).timeInterval).to(beCloseTo(DispatchTimeInterval.milliseconds(100).timeInterval))
				expect((DispatchTimeInterval.milliseconds(100) * 0.1).timeInterval).to(beCloseTo(DispatchTimeInterval.microseconds(10000).timeInterval))

				expect((DispatchTimeInterval.seconds(5) * 0.5).timeInterval).to(beCloseTo(DispatchTimeInterval.milliseconds(2500).timeInterval))
				expect((DispatchTimeInterval.seconds(1) * 0.25).timeInterval).to(beCloseTo(DispatchTimeInterval.milliseconds(250).timeInterval))
			}
			
			it("should not introduce integer overflow upon scale") {
				expect((DispatchTimeInterval.seconds(Int.max) * 0.01).timeInterval).to(beCloseTo(10 * DispatchTimeInterval.milliseconds(Int.max).timeInterval, within: 1))
				expect((DispatchTimeInterval.milliseconds(Int.max) * 0.01).timeInterval).to(beCloseTo(10 * DispatchTimeInterval.microseconds(Int.max).timeInterval, within: 1))
				expect((DispatchTimeInterval.microseconds(Int.max) * 0.01).timeInterval).to(beCloseTo(10 * DispatchTimeInterval.nanoseconds(Int.max).timeInterval, within: 1))
				expect((DispatchTimeInterval.seconds(Int.max) * 10).timeInterval) == Double.infinity
			}

			it("should produce the expected TimeInterval values") {
				expect(DispatchTimeInterval.seconds(1).timeInterval).to(beCloseTo(1.0))
				expect(DispatchTimeInterval.milliseconds(1).timeInterval).to(beCloseTo(0.001))
				expect(DispatchTimeInterval.microseconds(1).timeInterval).to(beCloseTo(0.000001, within: 0.0000001))
				expect(DispatchTimeInterval.nanoseconds(1).timeInterval).to(beCloseTo(0.000000001, within: 0.0000000001))

				expect(DispatchTimeInterval.milliseconds(500).timeInterval).to(beCloseTo(0.5))
				expect(DispatchTimeInterval.milliseconds(250).timeInterval).to(beCloseTo(0.25))
				expect(DispatchTimeInterval.never.timeInterval) == Double.infinity
			}

			it("should negate as you'd hope") {
				expect((-DispatchTimeInterval.seconds(1)).timeInterval).to(beCloseTo(-1.0))
				expect((-DispatchTimeInterval.milliseconds(1)).timeInterval).to(beCloseTo(-0.001))
				expect((-DispatchTimeInterval.microseconds(1)).timeInterval).to(beCloseTo(-0.000001, within: 0.0000001))
				expect((-DispatchTimeInterval.nanoseconds(1)).timeInterval).to(beCloseTo(-0.000000001, within: 0.0000000001))
				expect((-DispatchTimeInterval.never).timeInterval) == Double.infinity
			}
		}
	}
}
