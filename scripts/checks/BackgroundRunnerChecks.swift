import Foundation
@main struct Checks {
 @MainActor static func main() async throws {
   let client=OpenRouterActionClient.shared
   let job=BackgroundJob(title:"test",request:"test",status:.running,providerRaw:"openRouter",modelID:"stable")
   for kind: ProposedActionKind in [.openApp,.openWebsite,.remember] {
     client.proposals=[.init(kind:kind,title:"write",target:"x",response:"")]
     do { _ = try await BackgroundAgentRunner.run(job); assertionFailure() } catch is BackgroundActionNeedsReview {}
   }
   client.proposals=[.init(kind:.toolCall,title:"write",target:"write",response:"")]
   do { _ = try await BackgroundAgentRunner.run(job); assertionFailure() } catch is BackgroundActionNeedsReview {}
   assert(ActionRuntime.shared.calls.isEmpty)
   client.proposals=[.init(kind:.toolCall,title:"read",target:"read",response:""),.init(kind:.answer,title:"done",target:"",response:"answer https://example.com")]
   let answer=try await BackgroundAgentRunner.run(job)
   assert(answer.contains("https://example.com")); assert(ActionRuntime.shared.calls==["read"])
   client.proposals=[.init(kind:.toolCall,title:"read",target:"repeat",response:""),.init(kind:.toolCall,title:"read",target:"repeat",response:"")]
   do { _=try await BackgroundAgentRunner.run(job); assertionFailure() } catch {}
   assert(ActionRuntime.shared.calls.filter{$0=="repeat"}.count==1)
   let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".json")
   defer{try? FileManager.default.removeItem(at:file)}
   let queue=TaskScheduler(fileURL:file)
   queue.start{job in throw try BackgroundActionNeedsReview(request:job.request,proposal:.init(kind:.remember,title:"Remember",target:"fact",response:""),evidence:["read only"])}
   queue.enqueue(title:"Review",request:"remember")
   try await Task.sleep(for:.milliseconds(100))
   assert(queue.jobs.first?.status == .awaitingReview); assert(queue.jobs.first?.pendingProposalJSON != nil)
   queue.approveJob(queue.jobs[0].id)
   assert(queue.jobs.first?.status == .awaitingReview)
   queue.stop()
   print("PASS: mutation kinds blocked, tool review enforced, reads execute unapproved, results returned, repeated calls stop, scheduler review durable and cannot bypass")
 }
}
