import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../ui/food_image.dart';
import '../../ui/widgets.dart';
import 'record_form.dart';

Future<void> _openForm(
  BuildContext context,
  String title,
  Widget form,
  Future<void> Function() reload,
) async {
  await showForm<void>(context, title: title, builder: (_) => form);
  await reload();
}

String _preview(Object? text, [int max = 90]) {
  final s = (text ?? '').toString().replaceAll('\n', ' ').trim();
  return s.length <= max ? s : '${s.substring(0, max)}...';
}

// ---- Blog ------------------------------------------------------------

const _blogFields = [
  FieldSpec('title', 'Title', required: true),
  FieldSpec('title_bn', 'Title in Bangla'),
  FieldSpec('category', 'Category'),
  FieldSpec('excerpt', 'Short summary', kind: FieldKind.multiline, required: true),
  FieldSpec('excerpt_bn', 'Short summary in Bangla', kind: FieldKind.multiline),
  FieldSpec('body', 'Article', kind: FieldKind.multiline, required: true),
  FieldSpec('body_bn', 'Article in Bangla', kind: FieldKind.multiline),
  FieldSpec('slug', 'Web address ending', hint: 'lowercase-words-with-dashes'),
  FieldSpec('status', 'Status', kind: FieldKind.select, required: true, options: ['draft', 'published']),
];

/// Journal posts shown on the public website.
class BlogScreen extends StatelessWidget {
  const BlogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListModule(
      title: 'Blog',
      path: '/blog-posts',
      extract: (raw) => asRows((raw as Map?)?['posts']),
      itemBuilder: (context, p, reload) => Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: context.pageBg,
            child: Icon(Icons.article_outlined, color: context.brand, size: 20),
          ),
          title: Text('${p['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text([
            if ((p['category'] ?? '').toString().isNotEmpty) p['category'],
            _preview(p['excerpt'], 60),
          ].join('  -  ')),
          trailing: StatusChip(p['is_live'] == true ? 'published' : '${p['status']}'),
          onTap: () => _openForm(
            context,
            'Edit post',
            RecordForm(
              fields: _blogFields,
              initial: p,
              editing: true,
              path: '/blog-posts/${p['id']}',
              deletePath: '/blog-posts/${p['id']}',
              savedMessage: 'Post saved.',
            ),
            reload,
          ),
        ),
      ),
      fab: (reload) => FloatingActionButton.extended(
        onPressed: () => _openForm(
          context,
          'New post',
          const RecordForm(
            fields: _blogFields,
            path: '/blog-posts',
            initial: {'status': 'draft'},
            savedMessage: 'Post created.',
          ),
          reload,
        ),
        icon: const Icon(Icons.edit_note),
        label: const Text('Post'),
      ),
    );
  }
}

// ---- Careers ---------------------------------------------------------

const _employmentTypes = ['full_time', 'part_time', 'contract', 'internship'];
const _applicationStatuses = ['new', 'reviewing', 'shortlisted', 'rejected', 'hired'];

const _openingFields = [
  FieldSpec('title', 'Job title', required: true),
  FieldSpec('title_bn', 'Job title in Bangla'),
  FieldSpec('department', 'Department'),
  FieldSpec('employment_type', 'Type', kind: FieldKind.select, required: true, options: _employmentTypes),
  FieldSpec('summary', 'Short summary', kind: FieldKind.multiline, required: true),
  FieldSpec('description', 'Description', kind: FieldKind.multiline, required: true),
  FieldSpec('requirements', 'Requirements', kind: FieldKind.multiline),
  FieldSpec('closes_on', 'Closes on', kind: FieldKind.date),
  FieldSpec('is_active', 'Accepting applications', kind: FieldKind.toggle),
];

/// Job openings and the applications that came in through the website.
class CareersScreen extends StatefulWidget {
  const CareersScreen({super.key});

  @override
  State<CareersScreen> createState() => _CareersScreenState();
}

class _CareersScreenState extends State<CareersScreen> {
  final _body = GlobalKey<_CareersBodyState>();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Careers'),
          bottom: const TabBar(tabs: [Tab(text: 'Openings'), Tab(text: 'Applicants')]),
        ),
        floatingActionButton: Builder(
          builder: (context) => AnimatedBuilder(
            animation: DefaultTabController.of(context),
            builder: (context, _) => DefaultTabController.of(context).index == 0
                ? FloatingActionButton.extended(
                    onPressed: () async {
                      await showForm<void>(
                        context,
                        title: 'New opening',
                        builder: (_) => const RecordForm(
                          fields: _openingFields,
                          path: '/careers/openings',
                          savedMessage: 'Opening created.',
                        ),
                      );
                      await _body.currentState?.reload();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Opening'),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        body: _CareersBody(key: _body),
      ),
    );
  }
}

class _CareersBody extends StatefulWidget {
  const _CareersBody({super.key});

  @override
  State<_CareersBody> createState() => _CareersBodyState();
}

class _CareersBodyState extends State<_CareersBody> {
  final _key = GlobalKey<DataViewState<Map<String, dynamic>>>();

  Future<void> reload() async => _key.currentState?.reload();

  @override
  Widget build(BuildContext context) {
    return DataView<Map<String, dynamic>>(
      key: _key,
      path: '/careers',
      transform: (raw) => Map<String, dynamic>.from((raw as Map?) ?? const {}),
      builder: (context, data, raw, reload) {
        final openings = asRows(data['openings']);
        final applications = asRows(data['applications']);
        return TabBarView(children: [
          _list(
            context,
            openings,
            'No openings yet.',
            (o) => Card(
              child: ListTile(
                title: Text('${o['title']}'),
                subtitle: Text(
                  '${titleCase('${o['employment_type']}')}'
                  '${(o['department'] ?? '').toString().isEmpty ? '' : '  -  ${o['department']}'}'
                  '  -  ${o['applications_count']} applicant(s)',
                ),
                trailing: StatusChip(o['is_active'] == true ? 'open' : 'closed'),
                onTap: () => _openForm(
                  context,
                  'Edit opening',
                  RecordForm(
                    fields: _openingFields,
                    initial: o,
                    editing: true,
                    path: '/careers/openings/${o['id']}',
                    deletePath: '/careers/openings/${o['id']}',
                    deleteWarning: 'Its applications stay on file.',
                    savedMessage: 'Opening saved.',
                  ),
                  reload,
                ),
              ),
            ),
          ),
          _list(
            context,
            applications,
            'No applications yet.',
            (a) => Card(
              child: ListTile(
                title: Text('${a['name']}'),
                subtitle: Text([
                  if (a['job'] != null) a['job'],
                  if ((a['mobile'] ?? '').toString().isNotEmpty) a['mobile'],
                  fmtDay(a['created_at']),
                ].join('  -  ')),
                trailing: StatusChip('${a['status']}'),
                onTap: () => _openForm(
                  context,
                  'Applicant',
                  Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('${a['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    if ((a['email'] ?? '').toString().isNotEmpty) Text('${a['email']}'),
                    if ((a['mobile'] ?? '').toString().isNotEmpty) Text('${a['mobile']}'),
                    if ((a['message'] ?? '').toString().isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 8), child: Text('${a['message']}')),
                    if (a['has_cv'] == true)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('A CV is on file. Download it from the web admin.'),
                      ),
                    const SizedBox(height: 16),
                    RecordForm(
                      fields: const [
                        FieldSpec('status', 'Status', kind: FieldKind.select, required: true, options: _applicationStatuses),
                      ],
                      initial: a,
                      editing: true,
                      path: '/careers/applications/${a['id']}',
                      deletePath: '/careers/applications/${a['id']}',
                      deleteWarning: 'The application and its CV are removed.',
                      savedMessage: 'Applicant updated.',
                    ),
                  ]),
                  reload,
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }

  Widget _list(
    BuildContext context,
    List<Map<String, dynamic>> rows,
    String empty,
    Widget Function(Map<String, dynamic>) build,
  ) {
    if (rows.isEmpty) {
      return ListView(children: [const SizedBox(height: 120), EmptyState(empty)]);
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => build(rows[i]),
    );
  }
}

// ---- Letters ---------------------------------------------------------

const _letterFields = [
  FieldSpec('title', 'Title', required: true),
  FieldSpec('recipient', 'To'),
  FieldSpec('subject', 'Subject'),
  FieldSpec('body', 'Letter', kind: FieldKind.multiline, required: true),
  FieldSpec('letter_date', 'Date', kind: FieldKind.date, required: true),
];

/// Letters on the branch letterhead, printable as a PDF.
class LettersScreen extends StatelessWidget {
  const LettersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListModule(
      title: 'Letters',
      path: '/letters',
      query: {'branch_id': app.branchId},
      itemBuilder: (context, l, reload) => Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: context.pageBg,
            child: Icon(Icons.mail_outline, color: context.brand, size: 20),
          ),
          title: Text('${l['title']}'),
          subtitle: Text('${fmtDay(l['letter_date'])}  -  ${_preview(l['subject'] ?? l['body'], 50)}'),
          trailing: IconButton(
            tooltip: 'Print or share PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () async {
              try {
                final bytes = await app.api.getBytes('/letters/${l['id']}/pdf');
                await Printing.sharePdf(bytes: bytes, filename: 'letter-${l['id']}.pdf');
              } on ApiException catch (e) {
                if (context.mounted) {
                  snack(context, e.fullMessage, error: true);
                }
              }
            },
          ),
          onTap: () => _openForm(
            context,
            'Edit letter',
            RecordForm(
              fields: _letterFields,
              initial: l,
              editing: true,
              path: '/letters/${l['id']}',
              deletePath: '/letters/${l['id']}',
              extraBody: {'branch_id': app.branchId},
              savedMessage: 'Letter saved.',
            ),
            reload,
          ),
        ),
      ),
      fab: (reload) => FloatingActionButton.extended(
        onPressed: () => _openForm(
          context,
          'New letter',
          RecordForm(
            fields: _letterFields,
            path: '/letters',
            extraBody: {'branch_id': app.branchId},
            savedMessage: 'Letter saved.',
          ),
          reload,
        ),
        icon: const Icon(Icons.add),
        label: const Text('Letter'),
      ),
    );
  }
}

// ---- Media gallery ---------------------------------------------------

/// Photos and video links for the general gallery or one outlet. Photos are
/// uploaded from the web admin; here you can add video links, rename, hide,
/// re-order and delete.
class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  final _key = GlobalKey<DataViewState<Map<String, dynamic>>>();
  String? _owner;

  Future<void> _call(String method, String path, [Map<String, dynamic>? body]) async {
    final app = AppScope.read(context);
    final ok = await guarded(context, () async {
      if (method == 'POST') {
        await app.api.post(path, body: body);
      } else if (method == 'PUT') {
        await app.api.put(path, body: body);
      } else {
        await app.api.delete(path);
      }
    });
    if (ok) {
      await _key.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final canManage = app.can('media.manage');
    return Scaffold(
      appBar: AppBar(title: const Text('Media')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () async {
                await showForm<void>(
                  context,
                  title: 'Add video link',
                  builder: (_) => RecordForm(
                    fields: const [
                      FieldSpec('video_url', 'YouTube or Vimeo link', required: true, hint: 'https://'),
                      FieldSpec('title', 'Title'),
                    ],
                    path: '/media/videos',
                    extraBody: {'owner': _owner ?? 'general'},
                    savedMessage: 'Video added.',
                  ),
                );
                await _key.currentState?.reload();
              },
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('Video'),
            )
          : null,
      body: DataView<Map<String, dynamic>>(
        key: _key,
        path: '/media',
        query: _owner == null ? null : {'owner': _owner},
        transform: (raw) => Map<String, dynamic>.from((raw as Map?) ?? const {}),
        builder: (context, data, raw, reload) {
          final media = asRows(data['media']);
          final branches = asRows(data['branches']);
          final owner = _owner ?? '${data['owner']}';
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              DropdownButtonFormField<String>(
                initialValue: owner,
                decoration: const InputDecoration(labelText: 'Gallery'),
                items: [
                  if (data['can_use_general'] == true) const DropdownMenuItem(value: 'general', child: Text('General gallery')),
                  for (final b in branches) DropdownMenuItem(value: 'branch:${b['id']}', child: Text('${b['name']}')),
                ],
                onChanged: (v) {
                  setState(() => _owner = v);
                  WidgetsBinding.instance.addPostFrameCallback((_) => _key.currentState?.reload());
                },
              ),
              const SizedBox(height: 12),
              if (media.isEmpty) const EmptyState('Nothing in this gallery yet.'),
              for (var i = 0; i < media.length; i++)
                Card(
                  child: Column(children: [
                    ListTile(
                      leading: SizedBox(
                        width: 56,
                        height: 56,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: FoodImage(
                            url: media[i]['kind'] == 'video'
                                ? media[i]['thumbnail'] as String?
                                : foodImageUrl(app, {'cover_url': media[i]['src']}),
                          ),
                        ),
                      ),
                      title: Text(
                        (media[i]['title_en'] ?? '').toString().isEmpty
                            ? (media[i]['kind'] == 'video' ? 'Video' : 'Photo')
                            : '${media[i]['title_en']}',
                      ),
                      subtitle: Text(media[i]['kind'] == 'video' ? '${media[i]['provider'] ?? 'video'}' : 'Photo'),
                      trailing: media[i]['is_active'] == false ? const StatusChip('hidden') : null,
                      onTap: canManage
                          ? () => _openForm(
                                context,
                                'Edit media',
                                RecordForm(
                                  fields: const [
                                    FieldSpec('title', 'Title'),
                                    FieldSpec('title_bn', 'Title in Bangla'),
                                    FieldSpec('is_active', 'Shown on the website', kind: FieldKind.toggle),
                                  ],
                                  initial: {
                                    'title': media[i]['title_en'],
                                    'title_bn': media[i]['title_bn'],
                                    'is_active': media[i]['is_active'],
                                  },
                                  editing: true,
                                  path: '/media/${media[i]['id']}',
                                  deletePath: '/media/${media[i]['id']}',
                                  savedMessage: 'Media saved.',
                                ),
                                reload,
                              )
                          : null,
                    ),
                    if (canManage)
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        IconButton(
                          tooltip: 'Move up',
                          icon: const Icon(Icons.arrow_upward, size: 20),
                          onPressed: i == 0 ? null : () => _call('POST', '/media/${media[i]['id']}/move', {'direction': 'up'}),
                        ),
                        IconButton(
                          tooltip: 'Move down',
                          icon: const Icon(Icons.arrow_downward, size: 20),
                          onPressed: i == media.length - 1
                              ? null
                              : () => _call('POST', '/media/${media[i]['id']}/move', {'direction': 'down'}),
                        ),
                      ]),
                  ]),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---- Branches --------------------------------------------------------

const _branchFields = [
  FieldSpec('name', 'Name', required: true),
  FieldSpec('name_bn', 'Name in Bangla'),
  FieldSpec('code', 'Branch code', required: true, hint: 'e.g. BR01'),
  FieldSpec('phone', 'Phone', kind: FieldKind.phone),
  FieldSpec('address', 'Address'),
  FieldSpec('city', 'City'),
  FieldSpec('vat_percent', 'VAT percent', kind: FieldKind.number, required: true),
  FieldSpec('service_charge_percent', 'Service charge percent', kind: FieldKind.number, required: true),
  FieldSpec('vat_inclusive', 'Prices include VAT', kind: FieldKind.toggle),
  FieldSpec('allow_negative_stock', 'Allow selling out-of-stock items', kind: FieldKind.toggle),
  FieldSpec('online_ordering_enabled', 'Online ordering', kind: FieldKind.toggle),
  FieldSpec('receipt_footer', 'Receipt footer'),
  FieldSpec('is_active', 'Branch is active', kind: FieldKind.toggle),
];

/// Outlets: tax, service charge, contact details and switches. Detailed POS
/// layout settings stay in the web admin.
class BranchesScreen extends StatelessWidget {
  const BranchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final canManage = app.can('branches.manage');
    return ListModule(
      title: 'Branches',
      path: '/branches',
      itemBuilder: (context, b, reload) => Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: context.pageBg,
            child: Icon(Icons.storefront, color: context.brand, size: 20),
          ),
          title: Text('${localized(app, b)}  (${b['code']})'),
          subtitle: Text(
            '${(b['city'] ?? '').toString().isEmpty ? '' : '${b['city']}  -  '}'
            'VAT ${b['vat_percent']}%  -  Service ${b['service_charge_percent']}%',
          ),
          trailing: b['is_active'] == false ? const StatusChip('inactive') : null,
          onTap: canManage
              ? () => _openForm(
                    context,
                    'Edit branch',
                    RecordForm(
                      fields: _branchFields,
                      initial: b,
                      editing: true,
                      path: '/branches/${b['id']}',
                      deletePath: '/branches/${b['id']}',
                      deleteWarning: 'A branch with a menu or staff cannot be deleted.',
                      savedMessage: 'Branch saved.',
                    ),
                    reload,
                  )
              : null,
        ),
      ),
      fab: canManage
          ? (reload) => FloatingActionButton.extended(
                onPressed: () => _openForm(
                  context,
                  'New branch',
                  const RecordForm(
                    fields: _branchFields,
                    path: '/branches',
                    initial: {
                      'vat_percent': 5,
                      'service_charge_percent': 0,
                      'vat_inclusive': false,
                      'allow_negative_stock': false,
                      'online_ordering_enabled': true,
                      'is_active': true,
                    },
                    savedMessage: 'Branch created.',
                  ),
                  reload,
                ),
                icon: const Icon(Icons.add_business),
                label: const Text('Branch'),
              )
          : null,
    );
  }
}
