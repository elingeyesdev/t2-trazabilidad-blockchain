@unless(request()->routeIs('lotes.index'))
    @foreach(['success' => 'success', 'error' => 'danger', 'warning' => 'warning', 'info' => 'info'] as $key => $tone)
        @if(session($key))<div class="alert alert-{{ $tone }}" role="status">{{ session($key) }}</div>@endif
    @endforeach
    @if($errors->any())<div class="alert alert-danger" role="alert"><ul class="mb-0">@foreach($errors->all() as $message)<li>{{ $message }}</li>@endforeach</ul></div>@endif
@endunless
