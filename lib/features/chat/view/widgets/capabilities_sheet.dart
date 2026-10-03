import 'package:flutter/material.dart';

import '../../../../core/design/tokens.dart';

/// "See everything Ask AI can do" — the app's copy of the web chat's help popup
/// (`app/ask_ai.php`, `#aiCapsModal`): plain words, grouped by the job a person came to do.
///
/// The server's small-talk replies ("who are you", an off-topic ask) point here by this label,
/// so the label must stay the same as the web's.
///
/// An example marked `send` is a question and runs when tapped; the others only fill the box,
/// because a tap must never be how a to-do, invoice or email gets made by accident.
const capabilitiesLabel = 'See everything Ask AI can do';

class CapExample {
  const CapExample(this.text, {this.send = false});
  final String text;
  final bool send;
}

class CapGroup {
  const CapGroup(this.icon, this.title, this.body, this.examples, {this.note});
  final IconData icon;
  final String title;
  final String body;
  final List<CapExample> examples;
  final String? note;
}

/// Same groups, words and examples as the web popup, in the same order.
const capGroups = <CapGroup>[
  CapGroup(Icons.checklist_rounded, 'Tasks',
      'Find tasks, create one or hand it to someone, move it along, and log the hours spent on it.',
      [CapExample('Show my pending tasks', send: true), CapExample('Create a GST 3B task for ')]),
  CapGroup(Icons.receipt_long_outlined, 'Billing and invoices',
      'See who owes you and what is not billed yet. Create invoices, send them, mark them paid. '
          'Tap Preview to see the invoice exactly as it will look before you confirm it.',
      [CapExample('Who owes us money?', send: true), CapExample('Invoice all completed work for ')],
      note: 'Needs access to Accounts.'),
  CapGroup(Icons.mail_outline_rounded, 'Emails and missing documents',
      'Email a client their invoice, ask them for the documents still missing on a task, or send '
          'a short note. You read the whole email before it goes.',
      [
        CapExample('Which documents are missing on my open tasks?', send: true),
        CapExample('Ask the client for the missing documents on task '),
      ]),
  CapGroup(Icons.task_alt_rounded, 'To-dos and reminders',
      'Add, finish and list your to-dos. Set reminders for yourself or a colleague, in your own '
          'words: “tomorrow at 5”, “on the 18th”.',
      [CapExample('Show my to-dos', send: true), CapExample('Remind me to file GST on the 18th')]),
  CapGroup(Icons.people_outline_rounded, 'Clients',
      'Look a client up or list them by group or type. If an email, GSTIN, PAN, mobile number or '
          'billing address is missing, tap Enter information and fill it in right there — Ask AI '
          'then carries on by itself.',
      [CapExample('List clients', send: true)]),
  CapGroup(Icons.bar_chart_rounded, 'Attendance and reports',
      'Who was in, task counts by staff or client, and whether emails went out.',
      [CapExample('Who was in this week?', send: true), CapExample('Task report for this month', send: true)]),
  CapGroup(Icons.description_outlined, 'Documents',
      'Search every client file you can open, or ask a question and get an answer with the file '
          'it came from. On a task, each document shows the file that matches it and why — open it '
          'with View, then Confirm or say Not this.',
      [CapExample('Find the GST returns for ')]),
];

const _severalExamples = [
  CapExample('Show my to-dos and who owes us money?', send: true),
  CapExample('Add a to-do to call Ramesh and remind me at 5pm to send the GST file'),
];

/// Open the sheet. [onAsk] sends a question now; [onFill] puts an unfinished one in the box.
Future<void> showCapabilities(
  BuildContext context, {
  required void Function(String text) onAsk,
  required void Function(String text) onFill,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Ds.surface,
    builder: (sheet) {
      void tap(CapExample e) {
        Navigator.of(sheet).pop();
        e.send ? onAsk(e.text) : onFill(e.text);
      }

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(Ds.s4, 0, Ds.s4, Ds.s6),
          children: [
            Row(children: [
              const Icon(Icons.auto_awesome, color: Ds.blue, size: 20),
              const SizedBox(width: Ds.s2),
              Text('What can Ask AI do?', style: Theme.of(sheet).textTheme.titleLarge),
            ]),
            const SizedBox(height: Ds.s2),
            const Text(
              'Type what you want in your own words — a question or an instruction. Questions are '
              'answered straight away. Anything that creates, changes or sends something asks for '
              'your OK first.',
              style: TextStyle(color: Ds.inkSoft),
            ),
            const SizedBox(height: Ds.s4),
            for (final g in capGroups) _GroupCard(group: g, onTap: tap),
            _GroupCard(
              group: const CapGroup(Icons.library_add_check_outlined, 'Ask several things at once',
                  'Put a few requests in one message. Each one is done in turn, and anything that '
                      'needs your OK gets its own card.',
                  _severalExamples),
              onTap: tap,
            ),
            const _GroupCard(
              group: CapGroup(Icons.verified_user_outlined, 'What needs your OK',
                  'Creating or changing a task, an invoice, a payment or a fee, and every email, '
                      'first shows a card with exactly what will happen. Press Confirm to go ahead or '
                      'Cancel and nothing changes. Invoices and emails have a Preview button. A card '
                      'stays usable for 30 minutes.',
                  []),
              tint: Color(0xFFFFF7E6),
            ),
            const SizedBox(height: Ds.s2),
            const Text(
              'Tips. Use names as they appear in DocSync — a close spelling is fine and it will ask '
              'if two match. Say “send it to me” to try an email on yourself first. PAN, GSTIN, '
              'email addresses and phone numbers are never shown in the chat. It won’t edit or '
              'delete invoices, delete clients or tasks, or change anyone’s permissions — it tells '
              'you which page to use instead.',
              style: TextStyle(color: Ds.muted, fontSize: 13),
            ),
          ],
        ),
      );
    },
  );
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, this.onTap, this.tint});

  final CapGroup group;
  final void Function(CapExample)? onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: Ds.s3),
      padding: const EdgeInsets.all(Ds.s3),
      decoration: BoxDecoration(
        color: tint ?? Ds.surface,
        borderRadius: BorderRadius.circular(Ds.rChip),
        border: Border.all(color: Ds.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(group.icon, size: 18, color: Ds.blue),
            const SizedBox(width: Ds.s2),
            Expanded(
              child: Text(group.title,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(group.body, style: theme.textTheme.bodyMedium?.copyWith(color: Ds.inkSoft)),
          if (group.note != null) ...[
            const SizedBox(height: 4),
            Text(group.note!, style: theme.textTheme.bodySmall?.copyWith(color: Ds.muted)),
          ],
          if (group.examples.isNotEmpty) ...[
            const SizedBox(height: Ds.s2),
            Wrap(
              spacing: Ds.s2,
              runSpacing: Ds.s2,
              children: [
                for (final e in group.examples)
                  ActionChip(
                    avatar: Icon(e.send ? Icons.north_east_rounded : Icons.edit_outlined,
                        size: 16, color: Ds.blue),
                    label: Text(e.send ? e.text.trimRight() : '${e.text.trimRight()}…'),
                    tooltip: e.send ? 'Ask this now' : 'Put this in the box to finish',
                    backgroundColor: Ds.tint,
                    side: BorderSide.none,
                    onPressed: onTap == null ? null : () => onTap!(e),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
